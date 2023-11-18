module routing

import graph

fn test_contraction_hierarchies_preprocess_and_query() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	ch := ch_preprocess(&g, car)

	assert ch.nodes.len == g.node_count()
	assert ch.node_levels.len == g.node_count()

	// Levels should be a total permutation [0 .. N-1]
	mut levels := ch.node_levels.clone()
	levels.sort()
	for i in 0 .. levels.len {
		assert levels[i] == u32(i)
	}

	// Run Dijkstra baseline
	res_dijkstra := dijkstra_shortest_path(&g, 0, 8, car) or { panic('dijkstra failed') }

	// Run Contraction Hierarchies query
	res_ch := ch_query(&ch, 0, 8, &g) or { panic('ch query failed') }

	assert res_ch.found
	assert res_ch.duration_ms == res_dijkstra.duration_ms
	assert res_ch.node_path[0] == 0
	assert res_ch.node_path[res_ch.node_path.len - 1] == 8
}
