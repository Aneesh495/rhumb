# Spatial Indexing and Hilbert Curves

Spatial lookup is at the foundation of routing and map-matching. Given a geographic coordinate `(lat, lon)`, the engine must locate the nearest vertex or candidate road segment within microseconds.

Rhumb combines two spatial indexing paradigms:
1. A 28-bit 2D Hilbert Space-Filling Curve for compact 1D spatial sorting and spatial hashing.
2. A hierarchical R*-Tree for geometric bounding box intersection and branch-and-bound k-Nearest-Neighbor search.

---

## 1. 2D Hilbert Space-Filling Curve

A space-filling curve maps multi-dimensional space into a one-dimensional curve that passes through every point in the discrete domain while preserving spatial proximity: points that are close in 2D space are usually close in 1D memory order.

```
Order 1 (2x2)            Order 2 (4x4)             Order 3 (8x8)
  +---+                    +---+   +---+             +-+ +-+ +-+ +-+
  |   |                    |   |   |   |             | | | | | | | |
  +   +                    +   +---+   +             + +-+ +-+ +-+ +
  |   |                    |           |             |             |
  +---+                    +---+   +---+             +-+ +-+ +-+ +-+
```

### 1.1 28-Bit Coordinate Quantization

Given latitude in `[-90.0, +90.0]` and longitude in `[-180.0, +180.0]`:
1. Normalize and quantize coordinates into `2^28 = 268,435,456` integer bins:
   ```v
   x := u32(math.floor((lon + 180.0) / 360.0 * 268435455.0))
   y := u32(math.floor((lat + 90.0) / 180.0 * 268435455.0))
   ```
   At the equator, each bin corresponds to a spatial resolution of roughly 14.9 centimeters.

2. Bitwise Hilbert Transformation:
   The algorithm inspects the coordinate pair bit by bit from the most significant bit (order 27) down to the least significant bit (order 0). At each level:
   - Extract the 2-bit quadrant index: `rx = (x >> s) & 1`, `ry = (y >> s) & 1`.
   - Accumulate the 2-bit Hilbert value: `d += s * s * ((3 * rx) ^ ry)`.
   - Rotate the coordinate system if `ry == 0` to maintain continuous recursive orientation:
     ```v
     if ry == 0 {
         if rx == 1 {
             x = n - 1 - x
             y = n - 1 - y
         }
         t := x
         x = y
         y = t
     }
     ```

The resulting 64-bit unsigned integer represents the point along the 1D Hilbert traversal.

---

## 2. R*-Tree Spatial Index

While Hilbert curves provide 1D spatial ordering, range queries over arbitrary bounding boxes benefit from a tree-based hierarchical index.

### 2.1 Node Hierarchy and Invariants

The Rhumb R*-Tree organizes spatial bounding boxes into a balanced tree:
- Maximum node capacity: `M = 16` children.
- Minimum node capacity: `m = 4` children.
- Each inner node contains `(BBox2D, ChildPointer)` pairs, where `BBox2D` is the minimal bounding box enclosing all geometries in that child subtree.
- Each leaf node contains `(BBox2D, EdgeID)` pairs.

```
                                [ Root Node: BBox R ]
                               /                     \
                              v                       v
               [ Subtree Node A: BBox A ]   [ Subtree Node B: BBox B ]
               /            |           \
              v             v            v
         [ Leaf 1 ]    [ Leaf 2 ]    [ Leaf 3 ]
        (Edges 0..5)  (Edges 6..11) (Edges 12..15)
```

### 2.2 Bounding Box Window Search

To find all road segments intersecting a spatial bounding box `query`:
```v
pub fn (t &RTree) search_bbox(query BBox2D) []u32 {
    mut results := []u32{}
    t.search_node(t.root, query, mut results)
    return results
}
```
If `node.bbox.intersects(query)` is false, the entire subtree beneath `node` is immediately pruned, skipping thousands of candidate evaluations.

---

## 3. Branch-and-Bound k-Nearest-Neighbor Search

Finding the closest road segment to a GPS coordinate `P` is framed as a branch-and-bound priority queue search:

1. Maintain a min-heap of active candidate entries sorted by `min_dist_to_bbox(P, entry.bbox)`.
2. Push the root node onto the heap.
3. While the heap is non-empty:
   - Pop entry `E` with smallest lower-bound distance.
   - If `E` is a leaf entry (a road segment):
     - Compute exact perpendicular distance from `P` to segment geometry.
     - Add to settled nearest neighbors list.
     - If `k` neighbors have been found, update `max_settled_distance`.
   - If `E` is an inner node:
     - For each child `C` of `E`:
       - If `min_dist_to_bbox(P, C.bbox) < max_settled_distance`, push `C` onto the heap.

This strategy guarantees that subtrees that cannot possibly contain a closer point are never visited.

---

## 4. Empirical Performance

Benchmarked on Apple Silicon (M-series, 64-bit, `-prod` optimization):

| Search Method            | Total Time (1,000 queries) | Avg Latency | Throughput     | Speedup vs Scan |
| :----------------------- | :------------------------- | :---------- | :------------- | :-------------- |
| Linear Brute-Force Scan  | 16.30 ms                   | 16.3 us     | 61,342 qps     | 1.0x (baseline) |
| **Hilbert R*-Tree Index**| **1.50 ms**                | **1.5 us**  | **668,896 qps**| **10.9x faster**|

The R*-Tree achieves over 660,000 spatial queries per second, delivering sub-2-microsecond candidate generation during HMM map-matching.
