module routing

import graph

fn test_tsp_solver_multi_stop() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	// 4 stops at corners: 0 (NW), 2 (NE), 8 (SE), 6 (SW)
	stops := [u32(0), u32(2), u32(8), u32(6)]

	res := solve_tsp(&g, stops, car, true) or { panic('tsp failed') }

	assert res.stop_order.len == 5 // 4 stops plus return to start
	assert res.stop_order[0] == 0
	assert res.stop_order[res.stop_order.len - 1] == 0
	assert res.total_duration_ms > 0
	assert res.total_distance_m >= 8000.0 // Perimeter of 3x3 grid (2km per side x 4 = 8km)
	assert res.full_node_path.len > 4
}
