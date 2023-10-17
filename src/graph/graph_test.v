module graph

import core

fn test_graph_builder_and_csr_traversal() {
	mut builder := new_graph_builder()

	// Build a 4-node diamond graph in downtown San Francisco:
	//       1 (North)
	//      / \
	// 0(W)     2(E)
	//      \ /
	//       3 (South)
	n0 := builder.add_node(1001, core.Coord{
		lat: 37.7749, lon: -122.4200
	}, 10.0)
	n1 := builder.add_node(1002, core.Coord{
		lat: 37.7800, lon: -122.4150
	}, 12.0)
	n2 := builder.add_node(1003, core.Coord{
		lat: 37.7749, lon: -122.4100
	}, 15.0)
	n3 := builder.add_node(1004, core.Coord{
		lat: 37.7700, lon: -122.4150
	}, 8.0)

	assert n0 == 0
	assert n1 == 1
	assert n2 == 2
	assert n3 == 3

	// Add directed edges
	builder.add_edge(n0, n1, 500.0, 50.0, HighwayClass.primary, access_car | access_bike | access_foot,
		OnewayFlag.forward_only, SurfaceType.asphalt, 'Market St', []core.Coord{})
	builder.add_edge(n1, n2, 500.0, 50.0, HighwayClass.primary, access_car | access_bike | access_foot,
		OnewayFlag.forward_only, SurfaceType.asphalt, '4th St', []core.Coord{})
	builder.add_edge(n0, n3, 500.0, 30.0, HighwayClass.residential, access_car | access_bike | access_foot,
		OnewayFlag.forward_only, SurfaceType.asphalt, 'Mission St', []core.Coord{})
	builder.add_edge(n3, n2, 500.0, 30.0, HighwayClass.residential, access_car | access_bike | access_foot,
		OnewayFlag.forward_only, SurfaceType.asphalt, 'Howard St', []core.Coord{})

	g := builder.build()

	assert g.node_count() == 4
	assert g.edge_count() == 4

	// Verify forward star outgoing edges
	n0_out := g.out_edges(n0)
	assert n0_out.len == 2

	n1_out := g.out_edges(n1)
	assert n1_out.len == 1

	n2_out := g.out_edges(n2)
	assert n2_out.len == 0

	// Verify backward star incoming edges
	n2_in := g.in_edges(n2)
	assert n2_in.len == 2

	n0_in := g.in_edges(n0)
	assert n0_in.len == 0
}

fn test_graph_spatial_snapping() {
	mut builder := new_graph_builder()
	n0 := builder.add_node(1, core.Coord{
		lat: 37.7749, lon: -122.4200
	}, 0.0)
	n1 := builder.add_node(2, core.Coord{
		lat: 37.7749, lon: -122.4100
	}, 0.0)

	builder.add_edge(n0, n1, 800.0, 50.0, HighwayClass.primary, access_car, OnewayFlag.bidirectional,
		SurfaceType.asphalt, 'Main St', []core.Coord{})

	g := builder.build()

	// Query point near node 0
	near_n0 := core.Coord{
		lat: 37.7750
		lon: -122.4199
	}
	nearest_n := g.find_nearest_node(near_n0, 500.0) or { 999 }
	assert nearest_n == n0

	// Query point near the middle of the road segment
	mid_road := core.Coord{
		lat: 37.7752
		lon: -122.4150
	}
	edge_id, proj := g.find_nearest_edge(mid_road, 500.0) or {
		u32(999), core.PointProjection{}
	}
	assert edge_id == 0
	assert proj.distance_m < 50.0
	assert proj.fraction > 0.4 && proj.fraction < 0.6
}

fn test_vehicle_profile_cost_models() {
	mut builder := new_graph_builder()
	n0 := builder.add_node(1, core.Coord{
		lat: 37.0, lon: -122.0
	}, 0.0)
	n1 := builder.add_node(2, core.Coord{
		lat: 37.1, lon: -122.0
	}, 0.0)

	// Motorway edge (accessible to car, forbidden for foot)
	e_motorway := builder.add_edge(n0, n1, 10000.0, 100.0, HighwayClass.motorway, access_car,
		OnewayFlag.forward_only, SurfaceType.asphalt, 'Highway 101', []core.Coord{})

	g := builder.build()

	car := car_profile()
	foot := foot_profile()

	cost_car := g.edge_weight_ms(e_motorway, car)
	assert cost_car > 0 && cost_car < 600000 // Around 360,000 ms (6 minutes)

	cost_foot := g.edge_weight_ms(e_motorway, foot)
	assert cost_foot == 4294967295 // math.max_u32 (impassable)
}
