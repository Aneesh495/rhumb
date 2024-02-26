module main

import core
import graph
import routing

// RhumbGraphWrapper maintains state between graph construction and query evaluation.
@[heap]
pub struct RhumbGraphWrapper {
pub mut:
	builder   graph.GraphBuilder
	network   graph.Graph
	finalized bool
}

// CRouteResult mirrors the C struct rhumb_route_result layout.
@[heap]
pub struct CRouteResult {
pub mut:
	found             bool
	total_distance_m  f64
	total_duration_ms u32
	node_count        usize
	node_path         &u32 = unsafe { nil }
	edge_count        usize
	edge_path         &u32 = unsafe { nil }
	geometry_count    usize
	geometry          &core.Coord = unsafe { nil }
}

fn empty_c_route_result() &CRouteResult {
	return &CRouteResult{
		found: false
		total_distance_m: 0.0
		total_duration_ms: 0
		node_count: 0
		node_path: unsafe { nil }
		edge_count: 0
		edge_path: unsafe { nil }
		geometry_count: 0
		geometry: unsafe { nil }
	}
}

// rhumb_create_graph allocates and initializes a new graph builder handle.
@[export: 'rhumb_create_graph']
pub fn rhumb_create_graph() &RhumbGraphWrapper {
	mut b := graph.new_graph_builder()
	mut w := &RhumbGraphWrapper{
		builder: b
		network: graph.Graph{
			nodes: []graph.NodeAttribute{}
			edges: []graph.EdgeAttribute{}
			first_out: []u32{}
			first_in: []u32{}
			in_edges_list: []u32{}
			spatial_index: core.new_rtree()
		}
		finalized: false
	}
	return w
}

// rhumb_free_graph releases memory associated with graph handle.
@[export: 'rhumb_free_graph']
pub fn rhumb_free_graph(g &RhumbGraphWrapper) {
	if isnil(g) {
		return
	}
	unsafe {
		free(g)
	}
}

// rhumb_add_node appends a spatial vertex to the network builder.
@[export: 'rhumb_add_node']
pub fn rhumb_add_node(mut g RhumbGraphWrapper, osm_id i64, lat f64, lon f64, elevation_m f64) u32 {
	if g.finalized {
		return 0
	}
	return g.builder.add_node(osm_id, core.Coord{
		lat: lat
		lon: lon
	}, f32(elevation_m))
}

// rhumb_add_edge appends a directed road segment between vertices u and v.
@[export: 'rhumb_add_edge']
pub fn rhumb_add_edge(mut g RhumbGraphWrapper, u u32, v u32, length_m f64, speed_kph f32, name &char) u32 {
	if g.finalized {
		return 0
	}
	road_name := unsafe { cstring_to_vstring(name) }
	return g.builder.add_edge(u, v, length_m, speed_kph, graph.HighwayClass.primary,
		graph.access_car | graph.access_bike, graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt,
		road_name, []core.Coord{})
}

// rhumb_finalize_graph compiles the adjacency lists into CSR format and builds spatial indexes.
@[export: 'rhumb_finalize_graph']
pub fn rhumb_finalize_graph(mut g RhumbGraphWrapper) bool {
	if g.finalized {
		return true
	}
	g.network = g.builder.build()
	g.finalized = true
	return true
}

// rhumb_route_dijkstra computes standard shortest path using Dijkstra algorithm.
@[export: 'rhumb_route_dijkstra']
pub fn rhumb_route_dijkstra(g &RhumbGraphWrapper, from_lat f64, from_lon f64, to_lat f64, to_lon f64) &CRouteResult {
	if !g.finalized {
		return empty_c_route_result()
	}

	src_coord := core.Coord{
		lat: from_lat
		lon: from_lon
	}
	tgt_coord := core.Coord{
		lat: to_lat
		lon: to_lon
	}

	src_node := g.network.find_nearest_node(src_coord, 5000.0) or {
		return empty_c_route_result()
	}
	tgt_node := g.network.find_nearest_node(tgt_coord, 5000.0) or {
		return empty_c_route_result()
	}

	car := graph.car_profile()
	route := routing.dijkstra_shortest_path(&g.network, src_node, tgt_node, car) or {
		return empty_c_route_result()
	}

	return create_c_route_result(route)
}

// rhumb_route_astar computes goal-directed shortest path using A* search.
@[export: 'rhumb_route_astar']
pub fn rhumb_route_astar(g &RhumbGraphWrapper, from_lat f64, from_lon f64, to_lat f64, to_lon f64) &CRouteResult {
	if !g.finalized {
		return empty_c_route_result()
	}

	src_coord := core.Coord{
		lat: from_lat
		lon: from_lon
	}
	tgt_coord := core.Coord{
		lat: to_lat
		lon: to_lon
	}

	src_node := g.network.find_nearest_node(src_coord, 5000.0) or {
		return empty_c_route_result()
	}
	tgt_node := g.network.find_nearest_node(tgt_coord, 5000.0) or {
		return empty_c_route_result()
	}

	car := graph.car_profile()
	route := routing.astar_shortest_path(&g.network, src_node, tgt_node, car) or {
		return empty_c_route_result()
	}

	return create_c_route_result(route)
}

fn create_c_route_result(route routing.RouteResult) &CRouteResult {
	mut res := &CRouteResult{
		found: true
		total_distance_m: route.distance_m
		total_duration_ms: route.duration_ms
		node_count: usize(route.node_path.len)
		node_path: unsafe { nil }
		edge_count: usize(route.edge_path.len)
		edge_path: unsafe { nil }
		geometry_count: usize(route.geometry.len)
		geometry: unsafe { nil }
	}

	if route.node_path.len > 0 {
		unsafe {
			res.node_path = &u32(malloc(int(usize(route.node_path.len) * sizeof(u32))))
			vmemcpy(res.node_path, route.node_path.data, int(usize(route.node_path.len) * sizeof(u32)))
		}
	}

	if route.edge_path.len > 0 {
		unsafe {
			res.edge_path = &u32(malloc(int(usize(route.edge_path.len) * sizeof(u32))))
			vmemcpy(res.edge_path, route.edge_path.data, int(usize(route.edge_path.len) * sizeof(u32)))
		}
	}

	if route.geometry.len > 0 {
		unsafe {
			res.geometry = &core.Coord(malloc(int(usize(route.geometry.len) * sizeof(core.Coord))))
			vmemcpy(res.geometry, route.geometry.data, int(usize(route.geometry.len) * sizeof(core.Coord)))
		}
	}

	return res
}

// rhumb_free_route_result frees allocated route buffers.
@[export: 'rhumb_free_route_result']
pub fn rhumb_free_route_result(res &CRouteResult) {
	if isnil(res) {
		return
	}
	unsafe {
		if !isnil(res.node_path) {
			free(res.node_path)
		}
		if !isnil(res.edge_path) {
			free(res.edge_path)
		}
		if !isnil(res.geometry) {
			free(res.geometry)
		}
		free(res)
	}
}

// rhumb_distance_haversine computes Great-Circle distance.
@[export: 'rhumb_distance_haversine']
pub fn rhumb_distance_haversine(lat1 f64, lon1 f64, lat2 f64, lon2 f64) f64 {
	p1 := core.Coord{
		lat: lat1
		lon: lon1
	}
	p2 := core.Coord{
		lat: lat2
		lon: lon2
	}
	return core.haversine_distance_m(p1, p2)
}

// rhumb_distance_vincenty computes Vincenty ellipsoidal geodesic distance.
@[export: 'rhumb_distance_vincenty']
pub fn rhumb_distance_vincenty(lat1 f64, lon1 f64, lat2 f64, lon2 f64) f64 {
	p1 := core.Coord{
		lat: lat1
		lon: lon1
	}
	p2 := core.Coord{
		lat: lat2
		lon: lon2
	}
	return core.vincenty_distance_m(p1, p2) or { core.haversine_distance_m(p1, p2) }
}

// rhumb_version returns static version string.
@[export: 'rhumb_version']
pub fn rhumb_version() &char {
	return '0.1.0\x00'.str
}
