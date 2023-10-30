module routing

import graph

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
