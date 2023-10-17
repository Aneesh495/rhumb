module graph

import core

// GraphBuilder provides an incremental builder for constructing optimized CSR road graphs.
pub struct GraphBuilder {
pub mut:
	nodes    []NodeAttribute
	edges    []EdgeAttribute
	node_map map[i64]u32 // Mapping from external OSM ID to zero-based graph node index
}

// new_graph_builder initializes an empty graph builder.
pub fn new_graph_builder() GraphBuilder {
	return GraphBuilder{
		nodes: []NodeAttribute{}
		edges: []EdgeAttribute{}
		node_map: map[i64]u32{}
	}
}

// add_node inserts a vertex if not present or returns its existing zero-based index.
pub fn (mut b GraphBuilder) add_node(osm_id i64, coord core.Coord, elevation_m f32) u32 {
	if osm_id in b.node_map {
		return b.node_map[osm_id]
	}
	new_id := u32(b.nodes.len)
	b.nodes << NodeAttribute{
		node_id: new_id
		coord: coord
		elevation_m: elevation_m
		osm_id: osm_id
	}
	b.node_map[osm_id] = new_id
	return new_id
}

// add_edge appends a directed road segment to the network.
pub fn (mut b GraphBuilder) add_edge(source u32, target u32, length_m f64, speed_kph f32, highway HighwayClass, access u8, oneway OnewayFlag, surface SurfaceType, name string, geometry []core.Coord) u32 {
	edge_id := u32(b.edges.len)

	mut geom := geometry.clone()
	if geom.len == 0 {
		geom = [b.nodes[source].coord, b.nodes[target].coord]
	}

	bbox := core.bbox_from_points(geom)

	b.edges << EdgeAttribute{
		edge_id: edge_id
		source: source
		target: target
		length_m: length_m
		speed_kph: speed_kph
		highway: highway
		access: access
		oneway: oneway
		surface: surface
		name: name
		geometry: geom
		bbox: bbox
	}

	return edge_id
}

// build finalizes the graph into a cache-aligned Compressed Sparse Row (CSR) structure.
pub fn (mut b GraphBuilder) build() Graph {
	num_nodes := b.nodes.len
	num_edges := b.edges.len

	// Sort edges by source node to ensure forward CSR invariants
	b.edges.sort_with_compare(fn (e1 &EdgeAttribute, e2 &EdgeAttribute) int {
		if e1.source < e2.source {
			return -1
		}
		if e1.source > e2.source {
			return 1
		}
		if e1.target < e2.target {
			return -1
		}
		if e1.target > e2.target {
			return 1
		}
		return 0
	})

	// Re-index edge_id after sorting
	for i in 0 .. b.edges.len {
		b.edges[i].edge_id = u32(i)
	}

	// Construct forward star offsets first_out
	mut first_out := []u32{len: num_nodes + 1, init: 0}
	for edge in b.edges {
		first_out[edge.source + 1]++
	}
	for i in 0 .. num_nodes {
		first_out[i + 1] += first_out[i]
	}

	// Construct backward star offsets first_in and in_edges_list
	mut in_counts := []u32{len: num_nodes + 1, init: 0}
	for edge in b.edges {
		in_counts[edge.target + 1]++
	}
	mut first_in := []u32{len: num_nodes + 1, init: 0}
	for i in 0 .. num_nodes {
		first_in[i + 1] = first_in[i] + in_counts[i + 1]
	}

	mut current_in_pos := first_in.clone()
	mut in_edges_list := []u32{len: num_edges, init: 0}
	for edge in b.edges {
		pos := current_in_pos[edge.target]
		in_edges_list[pos] = edge.edge_id
		current_in_pos[edge.target]++
	}

	// Construct spatial index over edge bounding boxes
	mut spatial_index := core.new_rtree()
	for edge in b.edges {
		spatial_index.insert(edge.bbox, edge.edge_id)
	}

	return Graph{
		nodes: b.nodes.clone()
		edges: b.edges.clone()
		first_out: first_out
		first_in: first_in
		in_edges_list: in_edges_list
		spatial_index: spatial_index
	}
}
