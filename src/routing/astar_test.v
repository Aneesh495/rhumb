module routing

import graph

fn test_astar_optimality_and_equivalence() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	res_dijkstra := dijkstra_shortest_path(&g, 0, 8, car) or { panic('dijkstra failed') }
	res_astar := astar_shortest_path(&g, 0, 8, car) or { panic('astar failed') }
	res_bi_astar := bidirectional_astar(&g, 0, 8, car) or { panic('bi astar failed') }

	assert res_astar.found
	assert res_bi_astar.found

	// A* and Bidirectional A* must match Dijkstra optimal distance and duration
	assert res_astar.distance_m == res_dijkstra.distance_m
	assert res_astar.duration_ms == res_dijkstra.duration_ms

	assert res_bi_astar.distance_m == res_dijkstra.distance_m
	assert res_bi_astar.duration_ms == res_dijkstra.duration_ms

	assert res_astar.node_path[0] == 0
	assert res_astar.node_path[res_astar.node_path.len - 1] == 8
	assert res_bi_astar.node_path[0] == 0
	assert res_bi_astar.node_path[res_bi_astar.node_path.len - 1] == 8
}
