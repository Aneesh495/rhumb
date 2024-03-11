# Rhumb Architecture Specification

Rhumb is a high-performance geospatial routing, map-matching, and vector tile engine implemented from first principles. This document details the low-level systems architecture, memory layout, graph representations, and algorithmic pipelines powering the engine.

```
                           +------------------------------------------------+
                           |             Client Applications                |
                           |   (Web UI, CLI, Python SDK, C Shared Library)  |
                           +------------------------------------------------+
                                                   |
                     +-----------------------------+-----------------------------+
                     |                             |                             |
                     v                             v                             v
           +-------------------+         +-------------------+         +-------------------+
           | Embedded HTTP API |         |    Rhumb CLI      |         |   C Foreign ABI   |
           |   (Pico / REST)   |         | (Terminal Driver) |         |   (librhumb.so)   |
           +-------------------+         +-------------------+         +-------------------+
                     |                             |                             |
                     +-----------------------------+-----------------------------+
                                                   |
                                                   v
           +-------------------------------------------------------------------------------+
           |                            Engine Core Subsystems                             |
           +-------------------------------------------------------------------------------+
           |                                                                               |
           |  [ Routing Pipeline ]                  [ Spatial Indexing & Topology ]        |
           |  * Contraction Hierarchies (CH)        * Forward/Backward CSR Directed Graph  |
           |  * Bidirectional A* (ALT / Landmarks)  * 2D Hilbert R*-Tree Index             |
           |  * Isochrone Wavefront Expansion       * WGS84 Vincenty & Haversine Geodesy   |
           |  * Held-Karp & 2-Opt TSP Solver        * Sutherland-Hodgman Polygon Clipping  |
           |                                                                               |
           |  [ Map-Matching Engine ]               [ Vector Tile Dispatcher ]             |
           |  * Hidden Markov Model (HMM)           * Mapbox Vector Tile (MVT v2.1)        |
           |  * Gaussian Observation Emission       * Google Protocol Buffers Wire Encoder |
           |  * Exponential Transition Probability  * Web Mercator EPSG:3857 Projection    |
           |  * Gap-Resilient Viterbi Trellis DP    * Geometric Simplification (DP / VW)   |
           |                                                                               |
           +-------------------------------------------------------------------------------+
                                                   |
                                                   v
           +-------------------------------------------------------------------------------+
           |                                Storage Layer                                  |
           |  * Native Compressed Binary (.rhumb)   * GeoJSON Feature Collection           |
           |  * OpenStreetMap PBF (Blob / Zlib)     * GPX 1.1 Trajectory XML               |
           +-------------------------------------------------------------------------------+
```

---

## 1. Memory Layout and Graph Representation

Real-world road networks contain millions of vertices and directed edges. Storing graph topology using adjacency lists with heap-allocated pointers causes severe cache thrashing, pointer indirection overhead, and allocator fragmentation.

Rhumb eliminates pointer chasing by employing a dual Compressed Sparse Row (CSR) structure: Forward-Star for forward reachability, and Backward-Star for backward reachability.

### 1.1 Forward-Star and Backward-Star CSR

In Rhumb, the graph is composed of contiguous primitive arrays:

```
Nodes Array:   [Node 0] [Node 1] [Node 2] [Node 3] ... [Node N-1]
First-Out:     [  0   ] [  3   ] [  5   ] [  5   ] ... [  M   ]
Edges Array:   [Edge 0] [Edge 1] [Edge 2] [Edge 3] ... [Edge M-1]
```

- `first_out` is an array of size `N + 1`, where `first_out[u]` stores the index in `edges` where the outgoing edges of vertex `u` begin.
- The outgoing edges for vertex `u` are located precisely in the slice `edges[first_out[u] .. first_out[u + 1]]`.
- If `first_out[u] == first_out[u + 1]`, vertex `u` has an out-degree of zero.
- `first_in` and `in_edges_list` mirror this layout for backward traversals: `in_edges_list[first_in[v] .. first_in[v + 1]]` stores indices of all directed edges terminating at vertex `v`.

This representation achieves:
1. Exact memory compaction: no wasted pointer padding.
2. Contiguous cache-line prefetching during priority queue expansion.
3. O(1) degree lookup and O(deg(u)) neighbor iteration.

### 1.2 Structure Packing and Cache Alignment

Vertex coordinates and edge attributes are packed into compact structures to maximize L1/L2 cache efficiency:

```v
pub struct Coord {
pub:
    lat f64 // 8 bytes
    lon f64 // 8 bytes
} // 16 bytes total (fits exactly 4 coords per 64-byte cache line)

pub struct NodeAttribute {
pub:
    osm_id      i64   // 8 bytes
    coord       Coord // 16 bytes
    elevation_m f32   // 4 bytes
    _pad        u32   // 4 bytes explicit alignment
} // 32 bytes total (fits exactly 2 nodes per 64-byte cache line)
```

Each 64-byte CPU cache line holds exactly two node descriptors. When an algorithm scans adjacent vertices, sequential memory fetches saturate the hardware prefetcher without pipeline stalls.

---

## 2. Geodesic and Spatial Foundations

Accurate routing requires geodetically rigorous distance calculations that remain numerically stable across equatorial and polar regions.

### 2.1 WGS84 Geodesic Formulations

Rhumb implements two geodesic models:

1. **Vincenty Inverse Geodesic:**
   Solves the geodesic on the WGS84 reference ellipsoid:
   - Semi-major axis: `a = 6378137.0 m`
   - Flattening: `f = 1 / 298.257223563`
   - Semi-minor axis: `b = a * (1 - f) = 6356752.314245 m`
   Iteratively evaluates difference in longitude over the auxiliary sphere until convergence within `1e-12` radians (sub-millimeter precision).

2. **Haversine Great-Circle Approximation:**
   Evaluates spherical distance assuming mean Earth radius `R = 6371008.8 m`:
   `hav(theta) = sin^2(dlat / 2) + cos(lat1) * cos(lat2) * sin^2(dlon / 2)`
   `d = 2 * R * asin(sqrt(hav(theta)))`
   Used during inner loops of A* search and spatial pruning where sub-microsecond evaluation is critical.

### 2.2 Web Mercator Projection (EPSG:3857)

Vector tiles and web visualization operate in Spherical Web Mercator coordinates:
- `x = R * lon * (pi / 180)`
- `y = R * ln(tan(pi / 4 + lat * (pi / 360)))`

Tile pyramid indices `(z, x, y)` are computed via:
- `tile_x = floor((lon + 180.0) / 360.0 * 2^z)`
- `tile_y = floor((1.0 - asinh(tan(lat * pi / 180.0)) / pi) / 2.0 * 2^z)`

---

## 3. Spatial Indexing with Hilbert R*-Trees

Candidate retrieval for map-matching and nearest-node lookup requires querying millions of road segments in microseconds.

### 3.1 28-Bit Hilbert Space-Filling Curve

Rhumb projects 2D geographic coordinates `(lat, lon)` into a 1D 56-bit space-filling curve coordinate:
1. Coordinates are normalized and quantized into `2^28` discrete integer bins:
   - `x = floor((lon + 180.0) / 360.0 * (2^28 - 1))`
   - `y = floor((lat + 90.0) / 180.0 * (2^28 - 1))`
2. A state-driven bitwise transformation traverses the 28-order Hilbert curve to produce a 64-bit integer index.
3. Spatial proximity in 2D is preserved in 1D memory order, allowing efficient cache line locality during R-tree node construction.

### 3.2 R*-Tree Bounding Box Hierarchy

Road segments are indexed in a bounding-box tree with branching factor `M = 16`:
- Inner nodes store minimum bounding boxes enclosing all child subtrees.
- Leaf nodes store directed edge indices.
- Spatial range search tests box intersections using SIMD-friendly comparisons.
- Nearest-neighbor search uses branch-and-bound pruning with a priority queue ordered by minimum bounding box distance (`min_dist_to_bbox`), guaranteeing optimal search termination.

---

## 4. Multi-Modal Vehicle Routing

Edge travel time depends on vehicle capabilities, road surface, highway class, and legal access restrictions.

### 4.1 Vehicle Profiles

Rhumb defines four built-in vehicle profiles:
- `CarProfile`: Standard passenger vehicles; prioritizes motorways, trunks, and primary roads; penalizes residential roads; strictly respects oneway restrictions.
- `BicycleProfile`: Cyclists; prefers dedicated cycleways, paths, and tertiary roads; heavily penalizes high-speed arterial roads; permits bidirectional travel on pedestrian streets.
- `FootProfile`: Pedestrians; permits walking on footways, sidewalks, and tracks; ignores vehicular oneway restrictions; standard speed of 5.0 km/h.
- `HGVProfile`: Heavy goods vehicles; enforces minimum road class standards and weight class restrictions; reduces maximum speed on secondary networks.

### 4.2 Edge Weight Calculation

Each directed edge carries a dynamic travel duration:
`duration_ms = (length_m / speed_mps) * 1000.0 * penalty_factor`

If the vehicle profile lacks access flags for the edge (e.g. bicycle on motorway), the edge weight is evaluated as `infinity_weight (0xFFFFFFFF)`, immediately pruning it from heap exploration.
