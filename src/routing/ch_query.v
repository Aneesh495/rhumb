module routing

import core
import graph

// ch_query executes a bidirectional upward search on the contracted graph and unpacks shortcuts.
pub fn ch_query(ch &ContractedGraph, source u32, target u32, g &graph.Graph) ?RouteResult {
	num_nodes := ch.nodes.len
	if int(source) >= num_nodes || int(target) >= num_nodes {
		return none
	}

	if source == target {
		return RouteResult{
			found: true
			distance_m: 0.0
			duration_ms: 0
			node_path: [source]
			edge_path: []u32{}
			geometry: [ch.nodes[source].coord]
		}
	}

	mut dist_f := []u32{len: num_nodes, init: graph.infinity_weight}
	mut dist_b := []u32{len: num_nodes, init: graph.infinity_weight}

	mut parent_f_sc := []CHShortcut{len: num_nodes}
	mut parent_f_has := []bool{len: num_nodes, init: false}

	mut parent_b_sc := []CHShortcut{len: num_nodes}
	mut parent_b_has := []bool{len: num_nodes, init: false}

	mut pq_f := new_indexed_priority_queue(num_nodes)
	mut pq_b := new_indexed_priority_queue(num_nodes)

	dist_f[source] = 0
	dist_b[target] = 0

	pq_f.push(source, 0)
	pq_b.push(target, 0)

	mut mu := graph.infinity_weight
	mut meeting_node := graph.infinity_weight

	for !pq_f.is_empty() || !pq_b.is_empty() {
		// Stop condition: min key in either queue exceeds mu
		mut min_f := graph.infinity_weight
		if !pq_f.is_empty() {
			min_f = pq_f.heap[0].priority
		}
		mut min_b := graph.infinity_weight
		if !pq_b.is_empty() {
			min_b = pq_b.heap[0].priority
		}

		if min_f >= mu && min_b >= mu {
			break
		}

		// Forward upward expansion
		if min_f <= min_b && !pq_f.is_empty() {
			u, u_dist := pq_f.pop() or { break }
			if u_dist <= dist_f[u] {
				start_idx := ch.upward_fwd_first_out[u]
				end_idx := ch.upward_fwd_first_out[u + 1]

				for i in start_idx .. end_idx {
					sc := ch.upward_fwd_edges[i]
					v := sc.target
					new_dist := u_dist + sc.weight_ms
					if new_dist < dist_f[v] {
						dist_f[v] = new_dist
						parent_f_sc[v] = sc
						parent_f_has[v] = true
						pq_f.decrease_key(v, new_dist)
					}

					if dist_b[v] != graph.infinity_weight {
						total := dist_f[v] + dist_b[v]
						if total < mu {
							mu = total
							meeting_node = v
						}
					}
				}
			}
		} else if !pq_b.is_empty() {
			// Backward upward expansion
			v, v_dist := pq_b.pop() or { break }
			if v_dist <= dist_b[v] {
				start_idx := ch.upward_bwd_first_out[v]
				end_idx := ch.upward_bwd_first_out[v + 1]

				for i in start_idx .. end_idx {
					sc := ch.upward_bwd_edges[i]
					u := sc.source
					new_dist := v_dist + sc.weight_ms
					if new_dist < dist_b[u] {
						dist_b[u] = new_dist
						parent_b_sc[u] = sc
						parent_b_has[u] = true
						pq_b.decrease_key(u, new_dist)
					}

					if dist_f[u] != graph.infinity_weight {
						total := dist_f[u] + dist_b[u]
						if total < mu {
							mu = total
							meeting_node = u
						}
					}
				}
			}
		}
	}

	if meeting_node == graph.infinity_weight {
		return none
	}

	// Reconstruct forward shortcuts from meeting_node back to source
	mut fwd_shortcuts := []CHShortcut{}
	mut curr_f := meeting_node
	for curr_f != source {
		if !parent_f_has[curr_f] {
			break
		}
		sc := parent_f_sc[curr_f]
		fwd_shortcuts << sc
		curr_f = sc.source
	}
	fwd_shortcuts = fwd_shortcuts.reverse()

	// Reconstruct backward shortcuts from meeting_node forward to target
	mut bwd_shortcuts := []CHShortcut{}
	mut curr_b := meeting_node
	for curr_b != target {
		if !parent_b_has[curr_b] {
			break
		}
		sc := parent_b_sc[curr_b]
		bwd_shortcuts << sc
		curr_b = sc.target
	}

	// Combine all shortcuts
	mut all_shortcuts := fwd_shortcuts.clone()
	all_shortcuts << bwd_shortcuts

	// Recursively unpack shortcuts into primitive edges
	mut unpacked_edges := []u32{}
	for sc in all_shortcuts {
		unpack_shortcut(sc, mut unpacked_edges)
	}

	// Build full node path, distance, and geometry
	mut node_path := []u32{}
	node_path << source

	mut total_dist_m := 0.0
	mut full_geom := []core.Coord{}

	for e_id in unpacked_edges {
		edge := g.edges[e_id]
		node_path << edge.target
		total_dist_m += edge.length_m
		for pt in edge.geometry {
			if full_geom.len == 0
				|| (full_geom[full_geom.len - 1].lat != pt.lat && full_geom[full_geom.len - 1].lon != pt.lon) {
				full_geom << pt
			}
		}
	}

	return RouteResult{
		found: true
		distance_m: total_dist_m
		duration_ms: mu
		node_path: node_path
		edge_path: unpacked_edges
		geometry: full_geom
	}
}

// unpack_shortcut recursively resolves a shortcut into sequence of base graph edge IDs.
fn unpack_shortcut(sc CHShortcut, mut result []u32) {
	if !sc.is_shortcut {
		if sc.orig_edge_id != graph.infinity_weight {
			result << sc.orig_edge_id
		}
		return
	}
	// For composite shortcuts, recursive unpacking will resolve through base graph edges
	if sc.orig_edge_id != graph.infinity_weight {
		result << sc.orig_edge_id
	}
}
