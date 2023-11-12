module routing

import graph
import math

// CHShortcut represents an upward directed edge or contracted shortcut between two vertices.
pub struct CHShortcut {
pub mut:
	shortcut_id    u32
	source         u32
	target         u32
	weight_ms      u32
	distance_m     f64
	mid_node       u32 // Intermediate bypassed vertex, or infinity_weight if original edge
	orig_edge_id   u32 // Original edge index if not a composite shortcut
	is_shortcut    bool
}

// ContractedGraph stores the hierarchical node ordering and upward DAGs for bidirectional query.
pub struct ContractedGraph {
pub mut:
	nodes               []graph.NodeAttribute
	node_levels         []u32 // Contraction rank/level per node (0 to N-1)
	upward_fwd_edges    []CHShortcut
	upward_fwd_first_out []u32
	upward_bwd_edges    []CHShortcut
	upward_bwd_first_out []u32
}

// ch_preprocess transforms a base network graph into a hierarchically contracted graph under a vehicle profile.
pub fn ch_preprocess(g &graph.Graph, profile graph.VehicleProfile) ContractedGraph {
	num_nodes := g.node_count()
	if num_nodes == 0 {
		return ContractedGraph{
			nodes: []graph.NodeAttribute{}
			node_levels: []u32{}
			upward_fwd_edges: []CHShortcut{}
			upward_fwd_first_out: []u32{}
			upward_bwd_edges: []CHShortcut{}
			upward_bwd_first_out: []u32{}
		}
	}

	mut node_levels := []u32{len: num_nodes, init: graph.infinity_weight}
	mut contracted := []bool{len: num_nodes, init: false}

	// Adjacency lists for dynamic contraction graph (including injected shortcuts)
	mut adj_out := [][]CHShortcut{len: num_nodes}
	mut adj_in := [][]CHShortcut{len: num_nodes}

	mut shortcut_counter := u32(0)

	// Populate initial edges from base graph
	for e_id in 0 .. g.edges.len {
		edge := g.edges[e_id]
		cost := profile.compute_traversal_ms(edge)
		if cost == graph.infinity_weight {
			continue
		}

		sc := CHShortcut{
			shortcut_id: shortcut_counter
			source: edge.source
			target: edge.target
			weight_ms: cost
			distance_m: edge.length_m
			mid_node: graph.infinity_weight
			orig_edge_id: u32(e_id)
			is_shortcut: false
		}
		shortcut_counter++

		adj_out[edge.source] << sc
		adj_in[edge.target] << sc
	}

	// Priority queue of nodes to contract based on edge difference
	mut pq := new_indexed_priority_queue(num_nodes)
	for u in 0 .. num_nodes {
		ed := compute_edge_difference(u32(u), adj_out, adj_in, contracted)
		pq.push(u32(u), u32(math.max(0, ed + 10000))) // Offset by 10000 to keep non-negative
	}

	mut current_level := u32(0)

	for !pq.is_empty() {
		v, _ := pq.pop() or { break }

		// Recompute edge difference to account for dynamic neighbor contractions (lazy update)
		current_ed := compute_edge_difference(v, adj_out, adj_in, contracted)
		current_key := u32(math.max(0, current_ed + 10000))

		if !pq.is_empty() && current_key > pq.heap[0].priority {
			pq.push(v, current_key)
			continue
		}

		// Contract node v: find shortcuts between all incoming neighbors u and outgoing neighbors w
		contract_node(v, mut adj_out, mut adj_in, contracted, mut shortcut_counter)

		contracted[v] = true
		node_levels[v] = current_level
		current_level++
	}

	// Build upward forward and backward CSR graphs:
	// Upward forward graph: edges u -> v where level(v) > level(u)
	// Upward backward graph: edges v -> u where level(v) > level(u)
	mut upward_fwd_edges := []CHShortcut{}
	mut upward_bwd_edges := []CHShortcut{}

	for u in 0 .. num_nodes {
		u_level := node_levels[u]
		for sc in adj_out[u] {
			v := sc.target
			v_level := node_levels[v]
			if v_level > u_level {
				upward_fwd_edges << sc
			}
		}
		for sc in adj_in[u] {
			v := sc.source
			v_level := node_levels[v]
			if v_level > u_level {
				upward_bwd_edges << sc
			}
		}
	}

	// Build CSR for upward forward graph
	upward_fwd_edges.sort_with_compare(fn (a &CHShortcut, b &CHShortcut) int {
		if a.source < b.source {
			return -1
		}
		if a.source > b.source {
			return 1
		}
		return 0
	})
	mut fwd_first_out := []u32{len: num_nodes + 1, init: 0}
	for sc in upward_fwd_edges {
		fwd_first_out[sc.source + 1]++
	}
	for i in 0 .. num_nodes {
		fwd_first_out[i + 1] += fwd_first_out[i]
	}

	// Build CSR for upward backward graph (indexed by destination u where edge goes v -> u in backward sense)
	upward_bwd_edges.sort_with_compare(fn (a &CHShortcut, b &CHShortcut) int {
		if a.target < b.target {
			return -1
		}
		if a.target > b.target {
			return 1
		}
		return 0
	})
	mut bwd_first_out := []u32{len: num_nodes + 1, init: 0}
	for sc in upward_bwd_edges {
		bwd_first_out[sc.target + 1]++
	}
	for i in 0 .. num_nodes {
		bwd_first_out[i + 1] += bwd_first_out[i]
	}

	return ContractedGraph{
		nodes: g.nodes.clone()
		node_levels: node_levels
		upward_fwd_edges: upward_fwd_edges
		upward_fwd_first_out: fwd_first_out
		upward_bwd_edges: upward_bwd_edges
		upward_bwd_first_out: bwd_first_out
	}
}

// compute_edge_difference calculates ED(v) = shortcuts_needed(v) - uncontracted_edges(v).
fn compute_edge_difference(v u32, adj_out [][]CHShortcut, adj_in [][]CHShortcut, contracted []bool) int {
	mut in_count := 0
	for sc in adj_in[v] {
		if !contracted[sc.source] {
			in_count++
		}
	}

	mut out_count := 0
	for sc in adj_out[v] {
		if !contracted[sc.target] {
			out_count++
		}
	}

	shortcuts_needed := simulate_shortcuts(v, adj_out, adj_in, contracted)
	return shortcuts_needed - (in_count + out_count)
}

// simulate_shortcuts calculates the number of shortcuts that would be required if v is contracted.
fn simulate_shortcuts(v u32, adj_out [][]CHShortcut, adj_in [][]CHShortcut, contracted []bool) int {
	mut count := 0

	for in_sc in adj_in[v] {
		u := in_sc.source
		if contracted[u] || u == v {
			continue
		}

		for out_sc in adj_out[v] {
			w := out_sc.target
			if contracted[w] || w == v || u == w {
				continue
			}

			target_cost := in_sc.weight_ms + out_sc.weight_ms
			if !witness_path_exists(u, w, v, target_cost, adj_out, contracted) {
				count++
			}
		}
	}

	return count
}

// contract_node injects required shortcuts when contracting node v.
fn contract_node(v u32, mut adj_out [][]CHShortcut, mut adj_in [][]CHShortcut, contracted []bool, mut counter &u32) {
	for in_sc in adj_in[v] {
		u := in_sc.source
		if contracted[u] || u == v {
			continue
		}

		for out_sc in adj_out[v] {
			w := out_sc.target
			if contracted[w] || w == v || u == w {
				continue
			}

			target_cost := in_sc.weight_ms + out_sc.weight_ms
			if !witness_path_exists(u, w, v, target_cost, adj_out, contracted) {
				current_id := unsafe { *counter }
				unsafe {
					*counter = current_id + 1
				}

				sc := CHShortcut{
					shortcut_id: current_id
					source: u
					target: w
					weight_ms: target_cost
					distance_m: in_sc.distance_m + out_sc.distance_m
					mid_node: v
					orig_edge_id: graph.infinity_weight
					is_shortcut: true
				}

				adj_out[u] << sc
				adj_in[w] << sc
			}
		}
	}
}

// witness_path_exists runs a hop-limited Dijkstra search from u to w avoiding node v.
// Returns true if an alternative path of length <= max_cost exists.
fn witness_path_exists(u u32, w u32, v u32, max_cost u32, adj_out [][]CHShortcut, contracted []bool) bool {
	mut dist := map[u32]u32{}
	mut pq := new_indexed_priority_queue(adj_out.len)

	dist[u] = 0
	pq.push(u, 0)

	mut hops := 0
	max_hops := 20 // Bounded hop limit for witness search efficiency

	for !pq.is_empty() && hops < max_hops {
		curr, d := pq.pop() or { break }
		hops++

		if curr == w {
			return d <= max_cost
		}

		if d > max_cost {
			break
		}

		for sc in adj_out[curr] {
			nxt := sc.target
			if nxt == v || contracted[nxt] {
				continue
			}

			new_d := d + sc.weight_ms
			if new_d <= max_cost {
				if nxt !in dist || new_d < dist[nxt] {
					dist[nxt] = new_d
					pq.decrease_key(nxt, new_d)
				}
			}
		}
	}

	return false
}
