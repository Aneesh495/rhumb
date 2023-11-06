module routing

import core
import graph

// ALTRouter implements the ALT (A*, Landmarks, Triangle inequality) routing engine.
pub struct ALTRouter {
pub mut:
	landmarks          []u32
	dist_from_landmark [][]u32 // dist_from_landmark[L][u] = distance from landmark L to u in ms
	dist_to_landmark   [][]u32 // dist_to_landmark[L][u] = distance from u to landmark L in ms
}

// preprocess_alt selects landmarks via farthest-point sampling and computes all-pairs landmark distances.
pub fn preprocess_alt(g &graph.Graph, num_landmarks int, profile graph.VehicleProfile) ALTRouter {
	num_nodes := g.node_count()
	k := if num_landmarks > num_nodes { num_nodes } else { num_landmarks }

	if k == 0 || num_nodes == 0 {
		return ALTRouter{
			landmarks: []u32{}
			dist_from_landmark: [][]u32{}
			dist_to_landmark: [][]u32{}
		}
	}

	// Landmark selection: pick first landmark randomly/deterministically, then repeatedly pick farthest node
	mut landmarks := []u32{cap: k}
	landmarks << u32(0)

	for landmarks.len < k {
		// Run Dijkstra from last selected landmark to find the most distant reachable node
		last_l := landmarks[landmarks.len - 1]
		dist_from_last := run_dijkstra_from(g, last_l, profile)

		mut max_dist := u32(0)
		mut farthest_node := u32(0)

		for u in 0 .. num_nodes {
			d := dist_from_last[u]
			if d != graph.infinity_weight && d > max_dist {
				// Avoid picking existing landmarks
				if u32(u) !in landmarks {
					max_dist = d
					farthest_node = u32(u)
				}
			}
		}

		if max_dist == 0 {
			// Graph is disconnected or fully sampled
			break
		}
		landmarks << farthest_node
	}

	// Precompute distances from and to each selected landmark
	mut dist_from := [][]u32{cap: landmarks.len}
	mut dist_to := [][]u32{cap: landmarks.len}

	for l in landmarks {
		dist_from << run_dijkstra_from(g, l, profile)
		dist_to << run_dijkstra_to(g, l, profile)
	}

	return ALTRouter{
		landmarks: landmarks
		dist_from_landmark: dist_from
		dist_to_landmark: dist_to
	}
}

// heuristic_ms evaluates the triangle inequality lower bound across all precomputed landmarks.
pub fn (alt &ALTRouter) heuristic_ms(u u32, target u32) u32 {
	mut max_h := u32(0)

	for i in 0 .. alt.landmarks.len {
		// Bound 1: d(u, t) >= d(L, t) - d(L, u)
		d_l_t := alt.dist_from_landmark[i][target]
		d_l_u := alt.dist_from_landmark[i][u]
		if d_l_t != graph.infinity_weight && d_l_u != graph.infinity_weight && d_l_t > d_l_u {
			bound1 := d_l_t - d_l_u
			if bound1 > max_h {
				max_h = bound1
			}
		}

		// Bound 2: d(u, t) >= d(u, L) - d(t, L)
		d_u_l := alt.dist_to_landmark[i][u]
		d_t_l := alt.dist_to_landmark[i][target]
		if d_u_l != graph.infinity_weight && d_t_l != graph.infinity_weight && d_u_l > d_t_l {
			bound2 := d_u_l - d_t_l
			if bound2 > max_h {
				max_h = bound2
			}
		}
	}

	return max_h
}

// query performs goal-directed A* routing using the precomputed ALT landmark heuristic.
pub fn (alt &ALTRouter) query(g &graph.Graph, source u32, target u32, profile graph.VehicleProfile) ?RouteResult {
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
	mut g_score := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut open_set := new_indexed_priority_queue(num_nodes)
	g_score[source] = 0
	h0 := alt.heuristic_ms(source, target)
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

				h := alt.heuristic_ms(v, target)
				f_score := tentative_g + h
				open_set.decrease_key(v, f_score)
			}
		}
	}

	if !found {
		return none
	}

	// Reconstruct path
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

// run_dijkstra_from computes distances from root node to all reachable network nodes.
fn run_dijkstra_from(g &graph.Graph, root u32, profile graph.VehicleProfile) []u32 {
	num_nodes := g.node_count()
	mut dist := []u32{len: num_nodes, init: graph.infinity_weight}
	mut pq := new_indexed_priority_queue(num_nodes)

	dist[root] = 0
	pq.push(root, 0)

	for !pq.is_empty() {
		u, u_dist := pq.pop() or { break }
		if u_dist > dist[u] {
			continue
		}

		for e_id in g.out_edges(u) {
			edge := g.edges[e_id]
			cost := profile.compute_traversal_ms(edge)
			if cost == graph.infinity_weight {
				continue
			}
			v := edge.target
			new_dist := u_dist + cost
			if new_dist < dist[v] {
				dist[v] = new_dist
				pq.decrease_key(v, new_dist)
			}
		}
	}

	return dist
}

// run_dijkstra_to computes backward distances from all nodes to root node.
fn run_dijkstra_to(g &graph.Graph, root u32, profile graph.VehicleProfile) []u32 {
	num_nodes := g.node_count()
	mut dist := []u32{len: num_nodes, init: graph.infinity_weight}
	mut pq := new_indexed_priority_queue(num_nodes)

	dist[root] = 0
	pq.push(root, 0)

	for !pq.is_empty() {
		v, v_dist := pq.pop() or { break }
		if v_dist > dist[v] {
			continue
		}

		for e_id in g.in_edges(v) {
			edge := g.edges[e_id]
			cost := profile.compute_traversal_ms(edge)
			if cost == graph.infinity_weight {
				continue
			}
			u := edge.source
			new_dist := v_dist + cost
			if new_dist < dist[u] {
				dist[u] = new_dist
				pq.decrease_key(u, new_dist)
			}
		}
	}

	return dist
}
