module routing

import graph

fn test_isochrone_wavefront_and_buckets() {
	g := create_sample_grid_graph()
	car := graph.car_profile()

	// 3x3 grid: center is node 4
	// Thresholds: 100,000 ms (~1 hop away) and 200,000 ms (~2 hops away)
	buckets := [u32(100000), u32(200000)]
	result := compute_isochrones(&g, 4, buckets, car)

	assert result.buckets.len == 2
	assert result.buckets[0].duration_ms == 100000
	assert result.buckets[1].duration_ms == 200000

	// Larger time bucket should strictly contain equal or more reachable vertices
	assert result.buckets[1].reachable_nodes.len >= result.buckets[0].reachable_nodes.len
	assert result.buckets[0].reachable_nodes.len >= 1 // At least center itself

	// Outer polygon contour should be constructed
	assert result.buckets[1].polygon.len >= 3
}
