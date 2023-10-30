module routing

import core
import graph

// max_network_speed_mps defines the theoretical maximum velocity on the network (130 km/h) for admissible heuristics.
pub const max_network_speed_mps = 130.0 * 1000.0 / 3600.0 // ~36.11 m/s

// astar_heuristic_ms computes an admissible, monotonic lower bound on travel time in milliseconds.
@[inline]
pub fn astar_heuristic_ms(c1 core.Coord, c2 core.Coord) u32 {
	dist_m := core.haversine_distance_m(c1, c2)
	sec := dist_m / max_network_speed_mps
	return u32(sec * 1000.0)
}

// astar_shortest_path calculates the goal-directed optimal route from source to target using A* search.
pub fn astar_shortest_path(g &graph.Graph, source u32, target u32, profile graph.VehicleProfile) ?RouteResult {
	if int(source) >= g.node_count() || int(target) >= g.node_count() {
		return none
	}

	if source == target {
		return RouteResult{
			found: true
			distance_m: 0.0
			duration_ms: 0
			node_path: [source]
			edge_path: []u32{}
			geometry: [g.nodes[source].coord]
		}
	}

	num_nodes := g.node_count()
	target_coord := g.nodes[target].coord

	mut g_score := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut open_set := new_indexed_priority_queue(num_nodes)
	g_score[source] = 0
	h0 := astar_heuristic_ms(g.nodes[source].coord, target_coord)
	open_set.push(source, h0)

	mut found := false

	for !open_set.is_empty() {
		u, _ := open_set.pop() or { break }

		if u == target {
			found = true
			break
		}

		u_g := g_score[u]
		for e_id in g.out_edges(u) {
			edge := g.edges[e_id]
			cost := profile.compute_traversal_ms(edge)
			if cost == graph.infinity_weight {
				continue
			}

			v := edge.target
			tentative_g := u_g + cost

			if tentative_g < g_score[v] {
				g_score[v] = tentative_g
				parent_edge[v] = e_id
				parent_node[v] = u

				h := astar_heuristic_ms(g.nodes[v].coord, target_coord)
				f_score := tentative_g + h
				open_set.decrease_key(v, f_score)
			}
		}
	}

	if !found {
		return none
	}

	// Reconstruct path backward
	mut path_nodes := []u32{}
	mut path_edges := []u32{}
	mut curr := target

	for curr != source {
		path_nodes << curr
		e_id := parent_edge[curr]
		path_edges << e_id
		curr = parent_node[curr]
	}
	path_nodes << source
	path_nodes = path_nodes.reverse()
	path_edges = path_edges.reverse()

	mut total_dist_m := 0.0
	mut full_geom := []core.Coord{}

	for e_id in path_edges {
		edge := g.edges[e_id]
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
		duration_ms: g_score[target]
		node_path: path_nodes
		edge_path: path_edges
		geometry: full_geom
	}
}

// bidirectional_astar executes consistent symmetric bidirectional A* search.
pub fn bidirectional_astar(g &graph.Graph, source u32, target u32, profile graph.VehicleProfile) ?RouteResult {
	if int(source) >= g.node_count() || int(target) >= g.node_count() {
		return none
	}

	if source == target {
		return RouteResult{
			found: true
			distance_m: 0.0
			duration_ms: 0
			node_path: [source]
			edge_path: []u32{}
			geometry: [g.nodes[source].coord]
		}
	}

	num_nodes := g.node_count()
	source_coord := g.nodes[source].coord
	target_coord := g.nodes[target].coord

	// Symmetric potential function: p_f(u) = (h(u, t) - h(s, u)) / 2
	mut p_f := []i64{len: num_nodes, init: 0}
	for i in 0 .. num_nodes {
		h_t := i64(astar_heuristic_ms(g.nodes[i].coord, target_coord))
		h_s := i64(astar_heuristic_ms(source_coord, g.nodes[i].coord))
		p_f[i] = (h_t - h_s) / 2
	}

	mut g_f := []u32{len: num_nodes, init: graph.infinity_weight}
	mut g_b := []u32{len: num_nodes, init: graph.infinity_weight}

	mut parent_f_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_f_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut parent_b_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_b_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut pq_f := new_indexed_priority_queue(num_nodes)
	mut pq_b := new_indexed_priority_queue(num_nodes)

	g_f[source] = 0
	g_b[target] = 0

	f_source := if p_f[source] > 0 { u32(p_f[source]) } else { u32(0) }
	f_target := if -p_f[target] > 0 { u32(-p_f[target]) } else { u32(0) }

	pq_f.push(source, f_source)
	pq_b.push(target, f_target)

	mut mu := graph.infinity_weight
	mut meeting_node := graph.infinity_weight

	for !pq_f.is_empty() && !pq_b.is_empty() {
		top_f := pq_f.heap[0].priority
		top_b := pq_b.heap[0].priority

		if top_f + top_b >= mu {
			break
		}

		if top_f <= top_b {
			u, _ := pq_f.pop() or { break }
			u_g := g_f[u]

			for e_id in g.out_edges(u) {
				edge := g.edges[e_id]
				cost := profile.compute_traversal_ms(edge)
				if cost == graph.infinity_weight {
					continue
				}

				v := edge.target
				tentative_g := u_g + cost

				if tentative_g < g_f[v] {
					g_f[v] = tentative_g
					parent_f_edge[v] = e_id
					parent_f_node[v] = u

					val := i64(tentative_g) + p_f[v]
					key := if val > 0 { u32(val) } else { u32(0) }
					pq_f.decrease_key(v, key)
				}

				if g_b[v] != graph.infinity_weight {
					total := g_f[v] + g_b[v]
					if total < mu {
						mu = total
						meeting_node = v
					}
				}
			}
		} else {
			v, _ := pq_b.pop() or { break }
			v_g := g_b[v]

			for e_id in g.in_edges(v) {
				edge := g.edges[e_id]
				cost := profile.compute_traversal_ms(edge)
				if cost == graph.infinity_weight {
					continue
				}

				u := edge.source
				tentative_g := v_g + cost

				if tentative_g < g_b[u] {
					g_b[u] = tentative_g
					parent_b_edge[u] = e_id
					parent_b_node[u] = v

					val := i64(tentative_g) - p_f[u]
					key := if val > 0 { u32(val) } else { u32(0) }
					pq_b.decrease_key(u, key)
				}

				if g_f[u] != graph.infinity_weight {
					total := g_f[u] + g_b[u]
					if total < mu {
						mu = total
						meeting_node = u
					}
				}
			}
		}
	}

	if meeting_node == graph.infinity_weight {
		return none
	}

	// Reconstruct path through meeting node
	mut forward_nodes := []u32{}
	mut forward_edges := []u32{}
	mut curr_f := meeting_node
	for curr_f != source {
		forward_nodes << curr_f
		e_id := parent_f_edge[curr_f]
		forward_edges << e_id
		curr_f = parent_f_node[curr_f]
	}
	forward_nodes << source
	forward_nodes = forward_nodes.reverse()
	forward_edges = forward_edges.reverse()

	mut backward_nodes := []u32{}
	mut backward_edges := []u32{}
	mut curr_b := meeting_node
	for curr_b != target {
		e_id := parent_b_edge[curr_b]
		backward_edges << e_id
		curr_b = parent_b_node[curr_b]
		backward_nodes << curr_b
	}

	mut full_nodes := forward_nodes.clone()
	full_nodes << backward_nodes

	mut full_edges := forward_edges.clone()
	full_edges << backward_edges

	mut total_dist_m := 0.0
	mut full_geom := []core.Coord{}

	for e_id in full_edges {
		edge := g.edges[e_id]
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
		node_path: full_nodes
		edge_path: full_edges
		geometry: full_geom
	}
}
