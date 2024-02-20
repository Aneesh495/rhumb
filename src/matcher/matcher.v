module matcher

import core
import graph
import math
import routing

// MapMatcher coordinates spatial candidate generation and Viterbi sequence decoding on road networks.
pub struct MapMatcher {
pub:
	sigma_z       f64
	beta          f64
	search_radius f64
	max_gap_sec   f64
}

// new_map_matcher initializes a MapMatcher configured with Newson-Krumm default parameters.
pub fn new_map_matcher() MapMatcher {
	return MapMatcher{
		sigma_z: default_sigma_z
		beta: default_beta
		search_radius: 50.0 // 50 meter spatial candidate search window
		max_gap_sec: 120.0 // 2 minute temporal discontinuity threshold
	}
}

// match_trajectory aligns an ordered sequence of raw GPS fixes to the underlying road network graph.
pub fn (m &MapMatcher) match_trajectory(g &graph.Graph, trajectory []GPSPoint, profile graph.VehicleProfile) ?MatchResult {
	if trajectory.len == 0 {
		return none
	}

	if trajectory.len == 1 {
		pt := trajectory[0]
		edge_id, proj := g.find_nearest_edge(pt.coord, m.search_radius) or { return none }
		matched := MatchedPoint{
			original_gps: pt
			matched_coord: proj.projected_point
			edge_id: edge_id
			distance_m: proj.distance_m
			confidence: 1.0
		}
		return MatchResult{
			matched_points: [matched]
			matched_edges: [edge_id]
			matched_geometry: [proj.projected_point]
			total_distance_m: 0.0
			average_confidence: 1.0
		}
	}

	// Step 1: Candidate Generation
	mut candidates_by_step := [][]MatchCandidate{cap: trajectory.len}
	for pt in trajectory {
		candidates := m.find_candidates(g, pt)
		if candidates.len == 0 {
			// Fallback: broaden search radius if no candidate within initial window
			broader := m.find_candidates_with_radius(g, pt, m.search_radius * 2.0)
			candidates_by_step << broader
		} else {
			candidates_by_step << candidates
		}
	}

	// Verify at least one candidate step is non-empty
	mut has_candidates := false
	for c in candidates_by_step {
		if c.len > 0 {
			has_candidates = true
			break
		}
	}
	if !has_candidates {
		return none
	}

	// Step 2: Viterbi Trellis Forward DP
	num_steps := trajectory.len
	mut trellis := [][]f64{len: num_steps}
	mut backtrack := [][]int{len: num_steps}

	// Initialize step 0
	trellis[0] = []f64{len: candidates_by_step[0].len, init: -math.max_f64}
	backtrack[0] = []int{len: candidates_by_step[0].len, init: -1}

	for i in 0 .. candidates_by_step[0].len {
		trellis[0][i] = candidates_by_step[0][i].emission_log_prob
	}

	for t in 1 .. num_steps {
		prev_candidates := candidates_by_step[t - 1]
		curr_candidates := candidates_by_step[t]

		trellis[t] = []f64{len: curr_candidates.len, init: -math.max_f64}
		backtrack[t] = []int{len: curr_candidates.len, init: -1}

		if curr_candidates.len == 0 {
			continue
		}

		if prev_candidates.len == 0 {
			// Discontinuity reset: initialize from current emission
			for j in 0 .. curr_candidates.len {
				trellis[t][j] = curr_candidates[j].emission_log_prob
			}
			continue
		}

		euclidean_dist := core.haversine_distance_m(trajectory[t - 1].coord, trajectory[t].coord)

		for j in 0 .. curr_candidates.len {
			curr_cand := curr_candidates[j]
			mut max_prob := -math.max_f64
			mut best_prev := -1

			for i in 0 .. prev_candidates.len {
				if trellis[t - 1][i] <= -math.max_f64 {
					continue
				}

				prev_cand := prev_candidates[i]
				network_dist := m.compute_network_distance(g, prev_cand, curr_cand, profile)

				trans_log_p := transition_log_probability(euclidean_dist, network_dist, m.beta)
				total_p := trellis[t - 1][i] + trans_log_p + curr_cand.emission_log_prob

				if total_p > max_prob {
					max_prob = total_p
					best_prev = i
				}
			}

			if best_prev != -1 {
				trellis[t][j] = max_prob
				backtrack[t][j] = best_prev
			} else {
				// Fallback to pure emission probability
				trellis[t][j] = curr_cand.emission_log_prob
			}
		}
	}

	// Step 3: Backtrack Optimal State Sequence
	mut best_final_idx := -1
	mut max_final_prob := -math.max_f64
	mut best_final_step := -1

	// Search backwards for the latest step with valid trellis candidates
	for t := num_steps - 1; t >= 0; t-- {
		for j in 0 .. candidates_by_step[t].len {
			if trellis[t][j] > max_final_prob {
				max_final_prob = trellis[t][j]
				best_final_idx = j
				best_final_step = t
			}
		}
		if best_final_idx >= 0 {
			break
		}
	}

	mut matched_candidates := []MatchCandidate{len: num_steps}
	mut curr_idx := best_final_idx

	if best_final_step >= 0 {
		for t := best_final_step; t >= 0; t-- {
			if candidates_by_step[t].len == 0 {
				curr_idx = -1
				continue
			}
			if curr_idx < 0 || curr_idx >= candidates_by_step[t].len {
				mut best_j := 0
				mut best_p := -math.max_f64
				for j in 0 .. candidates_by_step[t].len {
					if trellis[t][j] > best_p {
						best_p = trellis[t][j]
						best_j = j
					}
				}
				curr_idx = best_j
			}
			matched_candidates[t] = candidates_by_step[t][curr_idx]
			curr_idx = backtrack[t][curr_idx]
		}

		for t in (best_final_step + 1) .. num_steps {
			if candidates_by_step[t].len > 0 {
				matched_candidates[t] = candidates_by_step[t][0]
			}
		}
	}

	// Step 4: Assemble Matched Points and Route Geometry
	mut matched_points := []MatchedPoint{cap: num_steps}
	mut matched_edges := []u32{}
	mut full_geom := []core.Coord{}
	mut total_dist_m := 0.0
	mut total_conf := 0.0

	for t in 0 .. num_steps {
		pt := trajectory[t]
		cand := matched_candidates[t]

		// Fallback to original GPS fix if candidate is empty or invalid
		is_valid_cand := cand.projected_coord.is_valid() && (cand.projected_coord.lat != 0.0 || cand.projected_coord.lon != 0.0)
		matched_coord := if is_valid_cand {
			cand.projected_coord
		} else {
			pt.coord
		}

		conf := if is_valid_cand {
			math.clamp(1.0 - cand.distance_m / m.search_radius, 0.0, 1.0)
		} else {
			0.1
		}
		total_conf += conf

		matched_points << MatchedPoint{
			original_gps: pt
			matched_coord: matched_coord
			edge_id: cand.edge_id
			distance_m: if is_valid_cand { cand.distance_m } else { 0.0 }
			confidence: conf
		}

		if is_valid_cand && (matched_edges.len == 0 || matched_edges[matched_edges.len - 1] != cand.edge_id) {
			matched_edges << cand.edge_id
		}
	}

	// Stitch road geometry between successive matched projections
	for i in 0 .. (matched_points.len - 1) {
		p1 := matched_points[i].matched_coord
		p2 := matched_points[i + 1].matched_coord
		total_dist_m += core.haversine_distance_m(p1, p2)
		full_geom << p1
	}
	if matched_points.len > 0 {
		full_geom << matched_points[matched_points.len - 1].matched_coord
	}

	avg_conf := if matched_points.len > 0 { total_conf / f64(matched_points.len) } else { 0.0 }

	return MatchResult{
		matched_points: matched_points
		matched_edges: matched_edges
		matched_geometry: full_geom
		total_distance_m: total_dist_m
		average_confidence: avg_conf
	}
}

// find_candidates locates road segment projections within default search radius.
fn (m &MapMatcher) find_candidates(g &graph.Graph, pt GPSPoint) []MatchCandidate {
	return m.find_candidates_with_radius(g, pt, m.search_radius)
}

fn (m &MapMatcher) find_candidates_with_radius(g &graph.Graph, pt GPSPoint, radius_m f64) []MatchCandidate {
	search_pad := radius_m / 111320.0
	query_box := core.new_bbox2d(pt.coord.lat - search_pad, pt.coord.lon - search_pad,
		pt.coord.lat + search_pad, pt.coord.lon + search_pad)
	candidate_edges := g.spatial_index.search_bbox(query_box)

	mut results := []MatchCandidate{}

	for e_id in candidate_edges {
		edge := g.edges[e_id]
		if edge.geometry.len < 2 {
			continue
		}

		for i in 0 .. (edge.geometry.len - 1) {
			proj := core.project_point_to_segment(pt.coord, edge.geometry[i], edge.geometry[i + 1])
			if proj.distance_m <= radius_m {
				log_p := emission_log_probability(proj.distance_m, m.sigma_z)
				results << MatchCandidate{
					edge_id: e_id
					projected_coord: proj.projected_point
					distance_m: proj.distance_m
					fraction: proj.fraction
					emission_log_prob: log_p
				}
				break // One best projection per edge is sufficient
			}
		}
	}

	return results
}

// compute_network_distance evaluates network travel distance between two candidate projections.
fn (m &MapMatcher) compute_network_distance(g &graph.Graph, c1 MatchCandidate, c2 MatchCandidate, profile graph.VehicleProfile) f64 {
	// If candidates lie on the exact same edge
	if c1.edge_id == c2.edge_id {
		edge := g.edges[c1.edge_id]
		if c2.fraction >= c1.fraction {
			return (c2.fraction - c1.fraction) * edge.length_m
		}
		// Moving backward on a oneway edge is penalized
		if edge.oneway == graph.OnewayFlag.forward_only {
			return 100000.0 // Heavy penalty
		}
		return (c1.fraction - c2.fraction) * edge.length_m
	}

	// Between different edges: route from target of edge1 to source of edge2
	edge1 := g.edges[c1.edge_id]
	edge2 := g.edges[c2.edge_id]

	dist_on_edge1 := (1.0 - c1.fraction) * edge1.length_m
	dist_on_edge2 := c2.fraction * edge2.length_m

	if edge1.target == edge2.source {
		return dist_on_edge1 + dist_on_edge2
	}

	res := routing.dijkstra_shortest_path(g, edge1.target, edge2.source, profile) or {
		return 50000.0 // Disconnected fallback penalty
	}
	return dist_on_edge1 + res.distance_m + dist_on_edge2
}
