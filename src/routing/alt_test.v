module routing

import graph

fn test_alt_preprocessing_and_routing() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	alt := preprocess_alt(&g, 4, car)
	assert alt.landmarks.len > 0
	assert alt.landmarks.len <= 4

	// Heuristic bound from node 0 to node 8 should be positive and <= true distance
	h := alt.heuristic_ms(0, 8)
	res_dijkstra := dijkstra_shortest_path(&g, 0, 8, car) or { panic('dijkstra failed') }

	assert h <= res_dijkstra.duration_ms

	// ALT query must match Dijkstra shortest path result
	res_alt := alt.query(&g, 0, 8, car) or { panic('alt query failed') }
	assert res_alt.found
	assert res_alt.duration_ms == res_dijkstra.duration_ms
	assert res_alt.distance_m == res_dijkstra.distance_m
	assert res_alt.node_path[0] == 0
	assert res_alt.node_path[res_alt.node_path.len - 1] == 8
}
