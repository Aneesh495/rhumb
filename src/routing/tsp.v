module routing

import core
import graph

// TSPResult encapsulates an optimized multi-stop sequence and stitched route geometry.
pub struct TSPResult {
pub mut:
	stop_order        []u32
	total_duration_ms u32
	total_distance_m  f64
	full_node_path    []u32
	full_geometry     []core.Coord
}

// solve_tsp computes an optimal or near-optimal visiting order visiting all specified stop nodes.
pub fn solve_tsp(g &graph.Graph, stops []u32, profile graph.VehicleProfile, return_to_start bool) ?TSPResult {
	k := stops.len
	if k == 0 {
		return none
	}

	if k == 1 {
		return TSPResult{
			stop_order: [stops[0]]
			total_duration_ms: 0
			total_distance_m: 0.0
			full_node_path: [stops[0]]
			full_geometry: [g.nodes[stops[0]].coord]
		}
	}

	// Compute all-pairs shortest path matrix between stops
	mut duration_matrix := [][]u32{len: k, init: []u32{len: k, init: 0}}
	mut leg_routes := map[string]RouteResult{}

	for i in 0 .. k {
		for j in 0 .. k {
			if i != j {
				u := stops[i]
				v := stops[j]
				res := dijkstra_shortest_path(g, u, v, profile) or { return none }
				duration_matrix[i][j] = res.duration_ms
				key := '${i}->${j}'
				leg_routes[key] = res
			}
		}
	}

	mut tour_indices := []int{cap: k + 1}

	if k <= 10 {
		tour_indices = solve_held_karp(duration_matrix, return_to_start)
	} else {
		tour_indices = solve_2opt(duration_matrix, return_to_start)
	}

	// Stitch final route
	mut ordered_stops := []u32{cap: tour_indices.len}
	for idx in tour_indices {
		ordered_stops << stops[idx]
	}

	mut total_dur := u32(0)
	mut total_dist := 0.0
	mut full_nodes := []u32{}
	mut full_geom := []core.Coord{}

	for step in 0 .. (tour_indices.len - 1) {
		from_idx := tour_indices[step]
		to_idx := tour_indices[step + 1]
		key := '${from_idx}->${to_idx}'
		route := leg_routes[key]

		total_dur += route.duration_ms
		total_dist += route.distance_m

		if step == 0 {
			full_nodes << route.node_path
			full_geom << route.geometry
		} else {
			// Skip first node to prevent duplication
			if route.node_path.len > 1 {
				full_nodes << route.node_path[1..]
			}
			if route.geometry.len > 1 {
				full_geom << route.geometry[1..]
			}
		}
	}

	return TSPResult{
		stop_order: ordered_stops
		total_duration_ms: total_dur
		total_distance_m: total_dist
		full_node_path: full_nodes
		full_geometry: full_geom
	}
}

// solve_held_karp evaluates exact optimal stop permutation via bitmask dynamic programming.
fn solve_held_karp(dist [][]u32, return_to_start bool) []int {
	n := dist.len
	num_states := 1 << n

	mut memo := [][]u32{len: num_states, init: []u32{len: n, init: graph.infinity_weight}}
	mut parent := [][]int{len: num_states, init: []int{len: n, init: -1}}

	memo[1][0] = 0 // Base state: visited only node 0

	for mask in 1 .. num_states {
		if (mask & 1) == 0 {
			continue // Start at node 0
		}
		for u in 0 .. n {
			if (mask & (1 << u)) == 0 || memo[mask][u] == graph.infinity_weight {
				continue
			}
			for v in 0 .. n {
				if (mask & (1 << v)) != 0 {
					continue
				}
				next_mask := mask | (1 << v)
				new_cost := memo[mask][u] + dist[u][v]
				if new_cost < memo[next_mask][v] {
					memo[next_mask][v] = new_cost
					parent[next_mask][v] = u
				}
			}
		}
	}

	full_mask := (1 << n) - 1
	mut best_end := -1
	mut min_total := graph.infinity_weight

	for u in 1 .. n {
		cost := if return_to_start {
			memo[full_mask][u] + dist[u][0]
		} else {
			memo[full_mask][u]
		}
		if cost < min_total {
			min_total = cost
			best_end = u
		}
	}

	// Backtrack tour
	mut path := []int{}
	mut curr := best_end
	mut mask := full_mask

	for curr != -1 {
		path << curr
		p := parent[mask][curr]
		mask ^= (1 << curr)
		curr = p
	}

	path = path.reverse()
	if return_to_start {
		path << 0
	}

	return path
}

// solve_2opt constructs an initial greedy tour and refines it via iterative 2-opt edge inversions.
fn solve_2opt(dist [][]u32, return_to_start bool) []int {
	n := dist.len
	mut visited := []bool{len: n, init: false}
	mut tour := []int{cap: n + 1}

	// Nearest neighbor heuristic initialization
	mut curr := 0
	tour << curr
	visited[curr] = true

	for tour.len < n {
		mut nearest := -1
		mut min_d := graph.infinity_weight

		for nxt in 0 .. n {
			if !visited[nxt] && dist[curr][nxt] < min_d {
				min_d = dist[curr][nxt]
				nearest = nxt
			}
		}

		if nearest == -1 {
			break
		}
		visited[nearest] = true
		tour << nearest
		curr = nearest
	}

	if return_to_start {
		tour << 0
	}

	// 2-opt refinement loop
	mut improved := true
	mut iterations := 0
	max_iter := 100

	for improved && iterations < max_iter {
		improved = false
		iterations++

		end_limit := if return_to_start { tour.len - 1 } else { tour.len }
		for i in 1 .. (end_limit - 1) {
			for j in (i + 1) .. end_limit {
				u1 := tour[i - 1]
				v1 := tour[i]
				u2 := tour[j]
				v2 := if j + 1 < tour.len { tour[j + 1] } else { tour[0] }

				curr_len := dist[u1][v1] + dist[u2][v2]
				new_len := dist[u1][u2] + dist[v1][v2]

				if new_len < curr_len {
					// Invert segment [i, j]
					mut l := i
					mut r := j
					for l < r {
						tmp := tour[l]
						tour[l] = tour[r]
						tour[r] = tmp
						l++
						r--
					}
					improved = true
				}
			}
		}
	}

	return tour
}
