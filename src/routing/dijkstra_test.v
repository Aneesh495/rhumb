module routing

import core
import graph

fn create_sample_grid_graph() graph.Graph {
	// Creates a 3x3 grid network:
	// 0 - 1 - 2
	// |   |   |
	// 3 - 4 - 5
	// |   |   |
	// 6 - 7 - 8
	mut builder := graph.new_graph_builder()

	for r in 0 .. 3 {
		for c in 0 .. 3 {
			osm_id := i64(r * 3 + c + 1)
			lat := 37.77 + f64(2 - r) * 0.01
			lon := -122.42 + f64(c) * 0.01
			builder.add_node(osm_id, core.Coord{
				lat: lat
				lon: lon
			}, 10.0)
		}
	}

	// Add horizontal edges
	for r in 0 .. 3 {
		for c in 0 .. 2 {
			u := u32(r * 3 + c)
			v := u32(r * 3 + c + 1)
			builder.add_edge(u, v, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'E-W St', []core.Coord{})
			builder.add_edge(v, u, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'E-W St', []core.Coord{})
		}
	}

	// Add vertical edges
	for r in 0 .. 2 {
		for c in 0 .. 3 {
			u := u32(r * 3 + c)
			v := u32((r + 1) * 3 + c)
			builder.add_edge(u, v, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'N-S Ave', []core.Coord{})
			builder.add_edge(v, u, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'N-S Ave', []core.Coord{})
		}
	}

	return builder.build()
}

fn test_dijkstra_shortest_path() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	// Shortest path from node 0 (NW corner) to node 8 (SE corner)
	res := dijkstra_shortest_path(&g, 0, 8, car) or { panic('route not found') }

	assert res.found
	assert res.node_path.len == 5 // 0 -> 1 -> 2 -> 5 -> 8 or Manhattan equivalent (4 hops = 5 nodes)
	assert res.node_path[0] == 0
	assert res.node_path[res.node_path.len - 1] == 8
	assert res.edge_path.len == 4
	assert res.distance_m == 4000.0
	assert res.duration_ms > 0
}

fn test_bidirectional_dijkstra_equivalence() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	res_uni := dijkstra_shortest_path(&g, 0, 8, car) or { panic('uni route not found') }
	res_bi := bidirectional_dijkstra(&g, 0, 8, car) or { panic('bi route not found') }

	assert res_uni.found
	assert res_bi.found
	// Both searches must yield identical duration and distance
	assert res_uni.duration_ms == res_bi.duration_ms
	assert res_uni.distance_m == res_bi.distance_m
	assert res_bi.node_path[0] == 0
	assert res_bi.node_path[res_bi.node_path.len - 1] == 8
}
