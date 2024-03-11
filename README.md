# Rhumb

```
  ____  _   _ _   _ __  __ ____  
 |  _ \| | | | | | |  \/  | __ ) 
 | |_) | |_| | | | | |\/| |  _ \ 
 |  _ <|  _  | |_| | |  | | |_) |
 |_| \_\_| |_|\___/|_|  |_|____/ 
```

**Rhumb** is an ultra high-performance geospatial routing, map-matching, and vector tile engine implemented from first principles in V. Designed for sub-millisecond query evaluation on continental road networks, Rhumb operates with zero runtime C library dependencies, zero allocator churn, and hardware-conscious memory locality.

Rhumb unifies hierarchical graph contraction, Hidden Markov Model trajectory alignment, space-filling curve spatial indexing, and on-the-fly Mapbox Vector Tile encoding into a single, cohesive engine.

---

## Performance Highlights

All benchmarks measured on Apple Silicon (M-series, 64-bit, `-prod` compiler optimization):

### Shortest Path Routing Throughput

| Algorithm                     | Mean Latency | Throughput         | Relative Speedup |
| :---------------------------- | :----------- | :----------------- | :--------------- |
| Standard Dijkstra             | 62.5 us      | 15,995 queries/sec | 1.0x (baseline)  |
| Bidirectional Dijkstra        | 42.4 us      | 23,590 queries/sec | 1.5x faster      |
| A* Search (Haversine)         | 51.1 us      | 19,579 queries/sec | 1.2x faster      |
| Bidirectional A* (ALT)        | 51.9 us      | 19,262 queries/sec | 1.2x faster      |
| **Contraction Hierarchies**   | **15.8 us**  | **63,472 queries/sec**| **4.0x faster**|

### Map-Matching and Spatial Indexing Throughput

| Pipeline Operation            | Mean Latency | Throughput            | Speedup vs Baseline |
| :---------------------------- | :----------- | :-------------------- | :------------------ |
| **HMM Viterbi Trellis Dec.**  | **4.8 us**   | **207,039 points/sec**| Real-time fleet sync|
| Linear Spatial Search         | 16.3 us      | 61,342 queries/sec    | 1.0x (baseline)     |
| **Hilbert R*-Tree Search**    | **1.5 us**   | **668,896 queries/sec**| **10.9x faster**   |

---

## System Architecture

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

## Core Technical Features

### 1. Dual Forward/Backward Compressed Sparse Row (CSR) Topology
- Replaces pointer-heavy adjacency lists with contiguous primitive arrays (`first_out`, `first_in`, `edges`).
- Cache-line aligned struct packing: exactly two vertex descriptors per 64-byte CPU cache line.
- O(1) degree lookup and zero-allocation edge iteration.

### 2. Contraction Hierarchies (CH)
- Preprocessing stage contracts vertices in order of increasing topological importance using an Edge Difference heuristic.
- Local Dijkstra witness path searches identify and inject shortcut edges, eliminating redundant nodes.
- Bidirectional upward query searches strictly along upward DAGs, settling routes in under 20 microseconds.

### 3. Hidden Markov Model (HMM) Map-Matching
- Implements the Newson-Krumm 2009 formulation for snapping noisy GPS traces onto road centerlines.
- Gaussian emission probability accounts for orthogonal GPS sensor variance.
- Exponential transition probability penalizes deviations between Euclidean trace distance and actual network routing distance.
- Log-space Viterbi trellis dynamic programming with automatic gap detection and discontinuity bridging.

### 4. 28-Bit Hilbert Space-Filling Curve & R*-Tree Indexing
- Quantizes 2D coordinates into a 56-bit integer space across 268 million bins per axis (14.9 cm equatorial resolution).
- Hierarchical R*-Tree index with branch-and-bound k-Nearest Neighbor search pruned by minimum bounding box distance.

### 5. Native MVT v2.1 Vector Tile Encoder
- Zero-dependency Google Protocol Buffers wire encoder supporting Varint, ZigZag, Fixed32, Fixed64, and Length-Delimited fields.
- Vector tile command stream synthesis (`MoveTo`, `LineTo`, `ClosePath`) for Web Mercator (EPSG:3857) tile pyramids.
- Built-in Douglas-Peucker and Visvalingam-Whyatt polyline simplification.

### 6. Multi-Modal Navigational Profiles & Guidance
- Dedicated vehicular profiles for Car, Bicycle, Foot, and Heavy Goods Vehicle (HGV).
- Turn maneuver classification (Slight Left, Sharp Right, U-Turn, Keep Straight) synthesized from relative azimuth deltas.

---

## Quickstart

### Prerequisites

- [V Compiler](https://vlang.io/) (version 0.4.x or 0.5.x)
- C compiler (Clang or GCC)
- Python 3.9+ (optional, for Python SDK)

### Building the Engine

```bash
# Clone the repository
git clone https://github.com/Aneesh495/rhumb.git
cd rhumb

# Compile the production CLI executable
v -prod -o bin/rhumb src

# Verify the build
./bin/rhumb version
```

### Running the Verification Suite

Rhumb includes a complete end-to-end verification pipeline:

```bash
bash scripts/run_all_tests.sh
```

This script automatically verifies:
1. All 21 V unit and integration test suites across every module.
2. C Foreign Function ABI compilation and test execution.
3. Python SDK unit test suite.
4. Codebase character hygiene (validating absolute zero em/en dashes).

---

## Command Line Interface

### 1. Shortest Path Routing

```bash
# Compute route between coordinates (latitude,longitude)
./bin/rhumb route --from 37.7850,-122.4150 --to 37.7730,-122.3990 --algo astar
```

Output:
```
ROUTE SUMMARY:
  Total Distance: 2720.0 meters (2.72 km)
  Travel Duration: 230.8 seconds (3.8 minutes)
  Nodes Traversed: 9
  Edges Traversed: 8

TURN-BY-TURN INSTRUCTIONS:
  1. Depart on Market St (350m)
  2. Continue straight onto Market St (350m)
  3. Turn right onto 3rd St (330m)
  4. Continue straight onto 3rd St (330m)
  5. Turn left onto Howard St (350m)
  6. Turn right onto 4th St (330m)
  7. Turn left onto Folsom St (350m)
  8. Turn right onto 5th St (330m)
  9. Arrive at destination on 5th St (0m)
```

### 2. GPS Trajectory Map-Matching

```bash
# Snap a noisy GPX trace onto the road network
./bin/rhumb match --gpx data/sample_traces/urban_delivery.gpx --output matched.geojson
```

### 3. Network Inspection

```bash
# Inspect graph topology and spatial index statistics
./bin/rhumb info data/san_francisco_downtown.geojson
```

### 4. Interactive Web Daemon

```bash
# Launch the embedded HTTP server and web visualizer
./bin/rhumb serve --port 8080
```

Open `http://localhost:8080` in your browser to access the interactive Leaflet visualizer:
- Click anywhere on the map to set Start and Destination markers.
- Select routing algorithms (Dijkstra, Bidirectional Dijkstra, A*, Bidirectional A*).
- Inspect live vector tiles, isochrone travel contours, and turn instructions.

---

## Embedded REST API

When running `rhumb serve`, the engine exposes a high-performance REST API:

| Endpoint | Method | Description |
| :------- | :----- | :---------- |
| `/api/v1/health` | GET | System health, version, and active vehicle profile |
| `/api/v1/route?from=lat,lon&to=lat,lon&algo=astar` | GET | Shortest path route and turn instructions |
| `/api/v1/match` | POST | HMM Viterbi trajectory map-matching |
| `/api/v1/isochrone?center=lat,lon&time=300` | GET | Reachable travel-time boundary polygon |
| `/tiles/{z}/{x}/{y}.mvt` | GET | Dynamic Mapbox Vector Tile protobuf |

---

## Multi-Language SDKs & Foreign ABI

### Python SDK

A full-featured Python client is included in `python/`:

```python
from rhumb import RhumbClient

client = RhumbClient(base_url="http://127.0.0.1:8080")

# Compute shortest path
route = client.route(
    from_coord=(37.7850, -122.4150),
    to_coord=(37.7730, -122.3990),
    algo="astar"
)
print(f"Distance: {route.distance_m:.1f} m, Duration: {route.duration_s:.1f} s")
for step in route.instructions:
    print(f"  {step.step_number}. {step.instruction_text}")

# Map-match raw GPS telemetry
matched = client.match([
    (37.7850, -122.4150),
    (37.7845, -122.4140),
    (37.7840, -122.4130)
])
print(f"Matched Distance: {matched.total_distance_m:.1f} m (Confidence: {matched.average_confidence:.1%})")
```

### C Foreign Function Interface (ABI)

Rhumb can be compiled as a standalone shared library (`librhumb.dylib` / `librhumb.so`) with native C headers in `c_api/include/rhumb.h`:

```c
#include <stdio.h>
#include "rhumb.h"

int main(void) {
    rhumb_graph_t* g = rhumb_create_graph();
    uint32_t n0 = rhumb_add_node(g, 1, 37.7740, -122.4200, 0.0);
    uint32_t n1 = rhumb_add_node(g, 2, 37.7780, -122.4200, 0.0);
    rhumb_add_edge(g, n0, n1, 450.0, 50.0f, "Market St");
    rhumb_finalize_graph(g);

    rhumb_route_result_t* res = rhumb_route_dijkstra(g, 37.7740, -122.4200, 37.7780, -122.4200);
    printf("Calculated route: %.1f meters\n", res->total_distance_m);

    rhumb_free_route_result(res);
    rhumb_free_graph(g);
    return 0;
}
```

Compile and run the C example:
```bash
cd c_api && make test
```

---

## Repository Structure

```
rhumb/
├── src/
│   ├── main.v                 # Engine CLI entrypoint
│   ├── app/                   # Subcommand routing and terminal formatting
│   ├── core/                  # Geodesic math, geometry algorithms, Hilbert R*-Tree
│   ├── graph/                 # CSR topology, vehicle profiles, and graph builder
│   ├── routing/               # Dijkstra, A*, Contraction Hierarchies, TSP, Isochrone
│   ├── matcher/               # Hidden Markov Model Viterbi map-matching
│   ├── tiles/                 # Protobuf wire encoder and MVT v2.1 vector tile engine
│   ├── formats/               # GeoJSON, GPX, Polyline, OSM PBF, and native .rhumb binary
│   ├── navigation/            # Relative azimuth calculations and turn guidance
│   └── server/                # Embedded HTTP daemon and REST API router
├── benches/                   # Micro-benchmark suites for routing, matching, spatial index
├── c_api/                     # C header (rhumb.h), shared library, and C verification
├── python/                    # Python SDK, dataclasses, and test suite
├── data/                      # Synthetic GeoJSON street networks and GPX traces
├── docs/                      # Architectural and mathematical documentation
│   ├── ARCHITECTURE.md
│   ├── CONTRACTION_HIERARCHIES.md
│   ├── MAP_MATCHING_HMM.md
│   └── SPATIAL_INDEXING.md
├── scripts/                   # Automated test runners and zero-dash character verifier
├── web/                       # Dark-mode Leaflet interactive web dashboard
└── v.mod                      # V module metadata
```

---

## Technical Documentation

For in-depth mathematical formulations and systems engineering details, refer to the documentation:

- [System Architecture Specification](docs/ARCHITECTURE.md)
- [Contraction Hierarchies Algorithm](docs/CONTRACTION_HIERARCHIES.md)
- [HMM Map-Matching Mathematical Formulation](docs/MAP_MATCHING_HMM.md)
- [Spatial Indexing with Hilbert R*-Trees](docs/SPATIAL_INDEXING.md)

---

## License

MIT License. Designed and crafted with precision by Aneesh Krishna.
