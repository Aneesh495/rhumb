module navigation

import core
import graph
import routing

fn test_turn_angles_and_maneuver_classification() {
	// Straight continuation (0 deg)
	assert calculate_turn_angle(90.0, 90.0) == 0.0
	assert classify_maneuver(0.0, 'Main St', 'Main St') == ManeuverType.continue_straight

	// Right turn (90 deg)
	assert calculate_turn_angle(0.0, 90.0) == 90.0
	assert classify_maneuver(90.0, 'Main St', 'Broadway') == ManeuverType.turn_right

	// Left turn (-90 deg)
	assert calculate_turn_angle(90.0, 0.0) == -90.0
	assert classify_maneuver(-90.0, 'Main St', 'Broadway') == ManeuverType.turn_left

	// U-turn (180 deg)
	assert calculate_turn_angle(0.0, 180.0) == 180.0
	assert classify_maneuver(175.0, 'Main St', 'Main St') == ManeuverType.u_turn
}

fn test_guidance_generation_on_route() {
	mut builder := graph.new_graph_builder()
	n0 := builder.add_node(1, core.Coord{
		lat: 37.7749, lon: -122.4200
	}, 0.0)
	n1 := builder.add_node(2, core.Coord{
		lat: 37.7749, lon: -122.4150
	}, 0.0)
	n2 := builder.add_node(3, core.Coord{
		lat: 37.7800, lon: -122.4150
	}, 0.0)

	// Leg 1: Heading East on Market St (bearing ~90 deg)
	builder.add_edge(n0, n1, 500.0, 50.0, graph.HighwayClass.primary, graph.access_car,
		graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Market St', []core.Coord{})
	// Leg 2: Turning North onto 4th St (bearing ~0 deg -> -90 deg left turn!)
	builder.add_edge(n1, n2, 600.0, 50.0, graph.HighwayClass.primary, graph.access_car,
		graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, '4th St', []core.Coord{})

	g := builder.build()
	car := graph.car_profile()

	route := routing.dijkstra_shortest_path(&g, n0, n2, car) or { panic('route failed') }
	steps := generate_guidance(&g, route)

	assert steps.len == 3 // Depart, Turn Left, Arrive
	assert steps[0].maneuver == ManeuverType.depart
	assert steps[0].instruction_text.contains('Depart on Market St')

	assert steps[1].maneuver == ManeuverType.turn_left
	assert steps[1].instruction_text.contains('Turn left onto 4th St')

	assert steps[2].maneuver == ManeuverType.arrive
	assert steps[2].instruction_text.contains('Arrive at destination')
}
