module routing

import core
import graph

// RouteResult packages shortest-path traversal metrics, node sequence, and fine-grained geometry.
pub struct RouteResult {
pub mut:
	found       bool
	distance_m  f64
	duration_ms u32
	node_path   []u32
	edge_path   []u32
	geometry    []core.Coord
}

// dijkstra_shortest_path calculates the optimal path between source and target using unidirectional Dijkstra search.
pub fn dijkstra_shortest_path(g &graph.Graph, source u32, target u32, profile graph.VehicleProfile) ?RouteResult {
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
	mut dist := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut pq := new_indexed_priority_queue(num_nodes)
	dist[source] = 0
	pq.push(source, 0)

	mut found := false

	for !pq.is_empty() {
		u, u_dist := pq.pop() or { break }

		if u == target {
			found = true
			break
		}

		if u_dist > dist[u] {
			continue
		}

		out_edges := g.out_edges(u)
		for e_id in out_edges {
			edge := g.edges[e_id]
			cost := profile.compute_traversal_ms(edge)
			if cost == graph.infinity_weight {
				continue
			}

			v := edge.target
			new_dist := u_dist + cost
			if new_dist < dist[v] {
				dist[v] = new_dist
				parent_edge[v] = e_id
				parent_node[v] = u
				pq.decrease_key(v, new_dist)
			}
		}
	}

	if !found {
		return none
	}

	// Reconstruct path backward from target to source
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

	// Accumulate distance and detailed geometry
	mut total_dist_m := 0.0
	mut full_geom := []core.Coord{}

	for i in 0 .. path_edges.len {
		edge := g.edges[path_edges[i]]
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
		duration_ms: dist[target]
		node_path: path_nodes
		edge_path: path_edges
		geometry: full_geom
	}
}

// bidirectional_dijkstra executes simultaneous forward and backward searches meeting at an intermediate junction.
pub fn bidirectional_dijkstra(g &graph.Graph, source u32, target u32, profile graph.VehicleProfile) ?RouteResult {
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
	mut dist_f := []u32{len: num_nodes, init: graph.infinity_weight}
	mut dist_b := []u32{len: num_nodes, init: graph.infinity_weight}

	mut parent_f_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_f_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut parent_b_edge := []u32{len: num_nodes, init: graph.infinity_weight}
	mut parent_b_node := []u32{len: num_nodes, init: graph.infinity_weight}

	mut visited_f := []bool{len: num_nodes, init: false}
	mut visited_b := []bool{len: num_nodes, init: false}

	mut pq_f := new_indexed_priority_queue(num_nodes)
	mut pq_b := new_indexed_priority_queue(num_nodes)

	dist_f[source] = 0
	dist_b[target] = 0

	pq_f.push(source, 0)
	pq_b.push(target, 0)

	mut mu := graph.infinity_weight // Best candidate path cost
	mut meeting_node := graph.infinity_weight

	for !pq_f.is_empty() && !pq_b.is_empty() {
		// Stop condition: smallest forward plus backward key >= current best mu
		top_f := pq_f.heap[0].priority
		top_b := pq_b.heap[0].priority
		if top_f + top_b >= mu {
			break
		}

		// Expand forward search
		if top_f <= top_b {
			u, u_dist := pq_f.pop() or { break }
			visited_f[u] = true

			for e_id in g.out_edges(u) {
				edge := g.edges[e_id]
				cost := profile.compute_traversal_ms(edge)
				if cost == graph.infinity_weight {
					continue
				}
				v := edge.target
				new_dist := u_dist + cost
				if new_dist < dist_f[v] {
					dist_f[v] = new_dist
					parent_f_edge[v] = e_id
					parent_f_node[v] = u
					pq_f.decrease_key(v, new_dist)
				}
				// Check meeting condition
				if visited_b[v] || dist_b[v] != graph.infinity_weight {
					total := dist_f[v] + dist_b[v]
					if total < mu {
						mu = total
						meeting_node = v
					}
				}
			}
		} else {
			// Expand backward search
			v, v_dist := pq_b.pop() or { break }
			visited_b[v] = true

			for e_id in g.in_edges(v) {
				edge := g.edges[e_id]
				cost := profile.compute_traversal_ms(edge)
				if cost == graph.infinity_weight {
					continue
				}
				u := edge.source
				new_dist := v_dist + cost
				if new_dist < dist_b[u] {
					dist_b[u] = new_dist
					parent_b_edge[u] = e_id
					parent_b_node[u] = v
					pq_b.decrease_key(u, new_dist)
				}
				// Check meeting condition
				if visited_f[u] || dist_f[u] != graph.infinity_weight {
					total := dist_f[u] + dist_b[u]
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

	// Reconstruct path: source -> meeting_node -> target
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
