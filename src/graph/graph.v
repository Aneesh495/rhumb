module graph

import core
import math

// Graph models road network topology using Compressed Sparse Row (CSR) forward and backward star arrays.
pub struct Graph {
pub mut:
	nodes         []NodeAttribute
	edges         []EdgeAttribute
	first_out     []u32 // Forward CSR offsets: length is nodes.len + 1
	first_in      []u32 // Backward CSR offsets: length is nodes.len + 1
	in_edges_list []u32 // Permutation of edge indices sorted by target node
	spatial_index core.RTree
}

// node_count returns the total number of vertices in the network.
pub fn (g &Graph) node_count() int {
	return g.nodes.len
}

// edge_count returns the total number of directed edges in the network.
pub fn (g &Graph) edge_count() int {
	return g.edges.len
}

// get_node retrieves metadata for the specified vertex identifier.
pub fn (g &Graph) get_node(id u32) NodeAttribute {
	return g.nodes[id]
}

// get_edge retrieves metadata for the specified edge identifier.
pub fn (g &Graph) get_edge(id u32) EdgeAttribute {
	return g.edges[id]
}

// out_edges returns an array of directed edge IDs originating at vertex u.
pub fn (g &Graph) out_edges(u u32) []u32 {
	if int(u) >= g.nodes.len {
		return []u32{}
	}
	start_idx := g.first_out[u]
	end_idx := g.first_out[u + 1]
	mut result := []u32{cap: int(end_idx - start_idx)}
	for i in start_idx .. end_idx {
		result << i
	}
	return result
}

// in_edges returns an array of directed edge IDs terminating at vertex v.
pub fn (g &Graph) in_edges(v u32) []u32 {
	if int(v) >= g.nodes.len {
		return []u32{}
	}
	start_idx := g.first_in[v]
	end_idx := g.first_in[v + 1]
	mut result := []u32{cap: int(end_idx - start_idx)}
	for i in start_idx .. end_idx {
		result << g.in_edges_list[i]
	}
	return result
}

// edge_weight_ms evaluates traversal duration in milliseconds for an edge under a given profile.
pub fn (g &Graph) edge_weight_ms(edge_id u32, profile VehicleProfile) u32 {
	if int(edge_id) >= g.edges.len {
		return infinity_weight
	}
	return profile.compute_traversal_ms(g.edges[edge_id])
}

// find_nearest_node locates the vertex closest to a given geographic coordinate.
pub fn (g &Graph) find_nearest_node(pt core.Coord, max_dist_m f64) ?u32 {
	mut best_node := u32(0)
	mut min_dist := max_dist_m
	mut found := false

	// Fast candidate query via R-tree
	search_pad := max_dist_m / 111320.0 // Roughly 111.32 km per degree
	query_box := core.new_bbox2d(pt.lat - search_pad, pt.lon - search_pad, pt.lat + search_pad,
		pt.lon + search_pad)
	candidate_edges := g.spatial_index.search_bbox(query_box)

	if candidate_edges.len > 0 {
		for e_id in candidate_edges {
			edge := g.edges[e_id]
			d_src := core.haversine_distance_m(pt, g.nodes[edge.source].coord)
			if d_src < min_dist {
				min_dist = d_src
				best_node = edge.source
				found = true
			}
			d_tgt := core.haversine_distance_m(pt, g.nodes[edge.target].coord)
			if d_tgt < min_dist {
				min_dist = d_tgt
				best_node = edge.target
				found = true
			}
		}
	} else {
		// Linear scan fallback
		for idx in 0 .. g.nodes.len {
			d := core.haversine_distance_m(pt, g.nodes[idx].coord)
			if d < min_dist {
				min_dist = d
				best_node = u32(idx)
				found = true
			}
		}
	}

	if found {
		return best_node
	}
	return none
}

// find_nearest_edge projects a coordinate onto the closest road edge within max_dist_m.
pub fn (g &Graph) find_nearest_edge(pt core.Coord, max_dist_m f64) ?(u32, core.PointProjection) {
	search_pad := max_dist_m / 111320.0
	query_box := core.new_bbox2d(pt.lat - search_pad, pt.lon - search_pad, pt.lat + search_pad,
		pt.lon + search_pad)
	candidate_edges := g.spatial_index.search_bbox(query_box)

	mut best_edge := u32(0)
	mut best_proj := core.PointProjection{
		projected_point: core.Coord{}
		distance_m: math.max_f64
		fraction: 0.0
	}
	mut found := false

	for e_id in candidate_edges {
		edge := g.edges[e_id]
		if edge.geometry.len < 2 {
			continue
		}
		for i in 0 .. (edge.geometry.len - 1) {
			proj := core.project_point_to_segment(pt, edge.geometry[i], edge.geometry[i + 1])
			if proj.distance_m < best_proj.distance_m && proj.distance_m <= max_dist_m {
				best_proj = proj
				best_edge = e_id
				found = true
			}
		}
	}

	if found {
		return best_edge, best_proj
	}
	return none
}
