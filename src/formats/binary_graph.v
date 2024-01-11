module formats

import core
import graph
import os

pub const binary_magic = 'RHUMB\x01\x00'

// save_graph_binary serializes the graph into compact native binary format (.rhumb).
pub fn save_graph_binary(g &graph.Graph, file_path string) ! {
	mut f := os.create(file_path)!
	defer {
		f.close()
	}

	// 1. Magic Header
	f.write(binary_magic.bytes())!

	// 2. Counts
	num_nodes := u32(g.nodes.len)
	num_edges := u32(g.edges.len)
	f.write_raw(num_nodes)!
	f.write_raw(num_edges)!

	// 3. Nodes
	for node in g.nodes {
		f.write_raw(node.node_id)!
		f.write_raw(node.coord.lat)!
		f.write_raw(node.coord.lon)!
		f.write_raw(node.elevation_m)!
		f.write_raw(node.osm_id)!
	}

	// 4. Edges
	for edge in g.edges {
		f.write_raw(edge.edge_id)!
		f.write_raw(edge.source)!
		f.write_raw(edge.target)!
		f.write_raw(edge.length_m)!
		f.write_raw(edge.speed_kph)!
		f.write_raw(u8(edge.highway))!
		f.write_raw(edge.access)!
		f.write_raw(u8(edge.oneway))!
		f.write_raw(u8(edge.surface))!

		// Write name string
		name_bytes := edge.name.bytes()
		name_len := u16(name_bytes.len)
		f.write_raw(name_len)!
		if name_len > 0 {
			f.write(name_bytes)!
		}

		// Write geometry coordinates
		geom_len := u32(edge.geometry.len)
		f.write_raw(geom_len)!
		for pt in edge.geometry {
			f.write_raw(pt.lat)!
			f.write_raw(pt.lon)!
		}
	}

	// 5. CSR Index Tables
	for offset in g.first_out {
		f.write_raw(offset)!
	}
	for offset in g.first_in {
		f.write_raw(offset)!
	}
	for e_id in g.in_edges_list {
		f.write_raw(e_id)!
	}
}

// load_graph_binary reads a native binary graph (.rhumb) from disk.
pub fn load_graph_binary(file_path string) !graph.Graph {
	mut f := os.open(file_path)!
	defer {
		f.close()
	}

	// 1. Verify Magic Header
	mut magic_buf := []u8{len: binary_magic.len}
	f.read(mut magic_buf)!
	if magic_buf.bytestr() != binary_magic {
		return error('invalid binary graph magic header')
	}

	// 2. Counts
	num_nodes := f.read_raw[u32]()!
	num_edges := f.read_raw[u32]()!

	// 3. Nodes
	mut nodes := []graph.NodeAttribute{cap: int(num_nodes)}
	for _ in 0 .. num_nodes {
		node_id := f.read_raw[u32]()!
		lat := f.read_raw[f64]()!
		lon := f.read_raw[f64]()!
		ele := f.read_raw[f32]()!
		osm_id := f.read_raw[i64]()!

		nodes << graph.NodeAttribute{
			node_id: node_id
			coord: core.Coord{
				lat: lat
				lon: lon
			}
			elevation_m: ele
			osm_id: osm_id
		}
	}

	// 4. Edges
	mut edges := []graph.EdgeAttribute{cap: int(num_edges)}
	mut spatial_index := core.new_rtree()

	for _ in 0 .. num_edges {
		edge_id := f.read_raw[u32]()!
		source := f.read_raw[u32]()!
		target := f.read_raw[u32]()!
		length_m := f.read_raw[f64]()!
		speed_kph := f.read_raw[f32]()!
		highway_u8 := f.read_raw[u8]()!
		access := f.read_raw[u8]()!
		oneway_u8 := f.read_raw[u8]()!
		surface_u8 := f.read_raw[u8]()!

		name_len := f.read_raw[u16]()!
		mut name := ''
		if name_len > 0 {
			mut name_bytes := []u8{len: int(name_len)}
			f.read(mut name_bytes)!
			name = name_bytes.bytestr()
		}

		geom_len := f.read_raw[u32]()!
		mut geom := []core.Coord{cap: int(geom_len)}
		for _ in 0 .. geom_len {
			pt_lat := f.read_raw[f64]()!
			pt_lon := f.read_raw[f64]()!
			geom << core.Coord{
				lat: pt_lat
				lon: pt_lon
			}
		}

		bbox := core.bbox_from_points(geom)
		spatial_index.insert(bbox, edge_id)

		edges << graph.EdgeAttribute{
			edge_id: edge_id
			source: source
			target: target
			length_m: length_m
			speed_kph: speed_kph
			highway: unsafe { graph.HighwayClass(highway_u8) }
			access: access
			oneway: unsafe { graph.OnewayFlag(oneway_u8) }
			surface: unsafe { graph.SurfaceType(surface_u8) }
			name: name
			geometry: geom
			bbox: bbox
		}
	}

	// 5. CSR Index Tables
	mut first_out := []u32{len: int(num_nodes) + 1}
	for i in 0 .. (int(num_nodes) + 1) {
		first_out[i] = f.read_raw[u32]()!
	}

	mut first_in := []u32{len: int(num_nodes) + 1}
	for i in 0 .. (int(num_nodes) + 1) {
		first_in[i] = f.read_raw[u32]()!
	}

	mut in_edges_list := []u32{len: int(num_edges)}
	for i in 0 .. int(num_edges) {
		in_edges_list[i] = f.read_raw[u32]()!
	}

	return graph.Graph{
		nodes: nodes
		edges: edges
		first_out: first_out
		first_in: first_in
		in_edges_list: in_edges_list
		spatial_index: spatial_index
	}
}
