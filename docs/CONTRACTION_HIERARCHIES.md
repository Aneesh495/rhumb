# Contraction Hierarchies (CH) Algorithm

Contraction Hierarchies (Geisberger, Sanders, Schultes, & Delling, 2008) is a speedup technique for shortest path computation on road networks. By preprocessing the road graph into a hierarchical overlay of upward shortcut edges, CH accelerates point-to-point shortest path queries from milliseconds down to single-digit microseconds, achieving speedups of 10x to 1000x over standard Dijkstra search.

---

## 1. Mathematical Formulation

Let `G = (V, E)` be a directed, weighted graph representing the road network with non-negative edge weight function `w: E -> R+`.

The goal of Contraction Hierarchies is to impose a total ordering `order: V -> {0, 1, ..., |V| - 1}` on the vertices such that:
1. Every vertex `v in V` is contracted in order of increasing importance.
2. Contracting a vertex `v` temporarily removes `v` from the remaining graph while preserving all shortest distances among the remaining uncontracted vertices.
3. For every pair of incoming neighbors `u` and outgoing neighbors `w` of `v`, if the path `u -> v -> w` is the unique shortest path between `u` and `w` in the remaining uncontracted graph, a directed shortcut edge `(u, w)` with weight `w(u, w) = w(u, v) + w(v, w)` is added to the graph.

```
       Before Contraction                     After Contracting Node v
       
               v (contracted)                          v
             /   \                                   /   \
            /     \                                 /     \
       e1  /       \ e2                        e1  /       \ e2
          v         v                             v         v
        u ----------> w                         u ----------> w
              P                                    Shortcut e*
        (if w(u,v)+w(v,w) < dist(u,w))             (bypasses v)
```

---

## 2. Node Ordering Heuristics

The order in which nodes are contracted dictates preprocessing duration and the number of shortcuts injected into the overlay. Rhumb evaluates node importance using a multi-factor priority metric:

### 2.1 Edge Difference Heuristic

The primary metric is Edge Difference:
`ED(v) = ShortcutsNeeded(v) - InDegree(v) - OutDegree(v)`

- If `ED(v) < 0`, contracting `v` reduces the total edge count in the remaining graph (e.g., dead ends or degree-2 vertices).
- If `ED(v) > 0`, contracting `v` increases the total edge count.

Nodes with lower edge differences are contracted first, preserving high-degree arterial transit nodes (e.g., highway junctions) for the final stages of contraction.

### 2.2 Witness Path Search

To determine whether a shortcut `(u, w)` is strictly required when contracting `v`, a local Dijkstra search (called a witness search) is performed from `u` to `w` in the uncontracted graph without traversing `v`:

```
MaxWeight = w(u, v) + w(v, w)
```

The witness search expands outward from `u` with a search horizon bounded by `MaxWeight` and a hop limit of 50 settled vertices.
- If a path from `u` to `w` is found with weight `dist(u, w) <= MaxWeight`, that path serves as a "witness", proving that `u -> v -> w` is not the unique shortest path. No shortcut is needed.
- If no such witness exists, the shortcut `(u, w)` is mandatory and is injected into the contracted graph.

---

## 3. Bidirectional Upward Query

Once all vertices have been assigned a hierarchical rank `level(v)`, the contracted graph is partitioned into two Directed Acyclic Graphs (DAGs):
1. **Upward Forward DAG:** Contains only edges `(u, v)` where `level(u) < level(v)`.
2. **Upward Backward DAG:** Contains only edges `(u, v)` where `level(v) < level(u)`.

### 3.1 Upward Search Algorithm

To answer a query between source `s` and target `t`:
1. Initialize a forward priority queue at `s` and a backward priority queue at `t`.
2. The forward search relaxes only outgoing edges that lead to strictly higher-ranked vertices: `level(neighbor) > level(current)`.
3. The backward search relaxes only incoming edges that lead to strictly higher-ranked vertices: `level(neighbor) > level(current)`.
4. Both search spaces meet at one or more shared candidate meeting nodes `M`:
   `dist(s, t) = min_{m in M} (dist_fwd(s, m) + dist_bwd(m, t))`
5. Because searches only proceed upward in rank, the number of settled vertices is typically bounded by `O(log |V|)` rather than `O(|V|)`, eliminating tens of thousands of edge relaxations.

```
                  Meeting Node M (Highest Rank)
                         /\
                        /  \
                       /    \
                      /      \
             Forward /        \ Backward
             Search /          \ Search
                   /            \
                  s              t
              (Source)        (Target)
```

---

## 4. Shortcut Unpacking and Route Reconstruction

Shortcut edges represent condensed multi-hop paths. Each shortcut stores a reference to its intermediate bypassed vertex: `mid_node`.

During query post-processing, Rhumb recursively expands shortcuts to retrieve the full vertex and edge sequence:

```v
fn unpack_shortcut(shortcut CHShortcut, mut node_path []u32) {
    if !shortcut.is_shortcut || shortcut.mid_node == infinity_weight {
        node_path << shortcut.target
        return
    }
    // Recursively expand first half (source -> mid)
    unpack_subpath(shortcut.source, shortcut.mid_node, mut node_path)
    // Recursively expand second half (mid -> target)
    unpack_subpath(shortcut.mid_node, shortcut.target, mut node_path)
}
```

The reconstructed path is 100% identical in distance, travel duration, and geometric shape to the path computed by full uncontracted Dijkstra search, but obtained with orders of magnitude fewer vertex expansions.
