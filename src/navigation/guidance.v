module navigation

import core
import graph
import math
import routing

// ManeuverType classifies turning maneuvers and directional cues for navigation.
pub enum ManeuverType {
	depart
	arrive
	continue_straight
	turn_slight_right
	turn_right
	turn_sharp_right
	turn_slight_left
	turn_left
	turn_sharp_left
	u_turn
	fork_left
	fork_right
	roundabout_exit
}

// StepInstruction packages a distinct navigational leg and human-readable spoken prompt.
pub struct StepInstruction {
pub mut:
	maneuver         ManeuverType
	street_name      string
	distance_m       f64
	duration_ms      u32
	instruction_text string
	location         core.Coord
	bearing_deg      f64
}

// generate_guidance transforms raw route edges and geometry into turn-by-turn navigation instructions.
pub fn generate_guidance(g &graph.Graph, route routing.RouteResult) []StepInstruction {
	if route.edge_path.len == 0 {
		if route.geometry.len > 0 {
			return [
				StepInstruction{
					maneuver: ManeuverType.arrive
					street_name: 'Destination'
					distance_m: 0.0
					duration_ms: 0
					instruction_text: 'You have arrived at your destination'
					location: route.geometry[0]
					bearing_deg: 0.0
				},
			]
		}
		return []StepInstruction{}
	}

	mut steps := []StepInstruction{}
	num_edges := route.edge_path.len

	// First edge: Depart maneuver
	e0 := g.edges[route.edge_path[0]]
	initial_b := if e0.geometry.len >= 2 {
		core.initial_bearing_deg(e0.geometry[0], e0.geometry[1])
	} else {
		0.0
	}

	steps << StepInstruction{
		maneuver: ManeuverType.depart
		street_name: e0.name
		distance_m: e0.length_m
		duration_ms: 0
		instruction_text: 'Depart on ${e0.name}'
		location: g.nodes[e0.source].coord
		bearing_deg: initial_b
	}

	for i in 1 .. num_edges {
		prev_e := g.edges[route.edge_path[i - 1]]
		curr_e := g.edges[route.edge_path[i]]

		// Calculate incoming and outgoing bearings at transition vertex
		mut in_b := 0.0
		if prev_e.geometry.len >= 2 {
			in_b = core.final_bearing_deg(prev_e.geometry[prev_e.geometry.len - 2], prev_e.geometry[prev_e.geometry.len - 1])
		}

		mut out_b := 0.0
		if curr_e.geometry.len >= 2 {
			out_b = core.initial_bearing_deg(curr_e.geometry[0], curr_e.geometry[1])
		}

		turn_angle := calculate_turn_angle(in_b, out_b)
		maneuver := classify_maneuver(turn_angle, prev_e.name, curr_e.name)
		text := synthesize_instruction(maneuver, curr_e.name)

		steps << StepInstruction{
			maneuver: maneuver
			street_name: curr_e.name
			distance_m: curr_e.length_m
			duration_ms: 0
			instruction_text: text
			location: g.nodes[curr_e.source].coord
			bearing_deg: out_b
		}
	}

	// Final step: Arrive maneuver
	last_edge := g.edges[route.edge_path[num_edges - 1]]
	steps << StepInstruction{
		maneuver: ManeuverType.arrive
		street_name: last_edge.name
		distance_m: 0.0
		duration_ms: 0
		instruction_text: 'Arrive at destination on ${last_edge.name}'
		location: g.nodes[last_edge.target].coord
		bearing_deg: 0.0
	}

	return steps
}

// calculate_turn_angle returns relative turn angle in degrees [-180.0, 180.0] (positive for right, negative for left).
pub fn calculate_turn_angle(in_bearing f64, out_bearing f64) f64 {
	mut diff := out_bearing - in_bearing
	for diff > 180.0 {
		diff -= 360.0
	}
	for diff < -180.0 {
		diff += 360.0
	}
	return diff
}

// classify_maneuver maps a turn angle and road name transition into a typed maneuver.
pub fn classify_maneuver(angle f64, prev_name string, curr_name string) ManeuverType {
	abs_angle := math.abs(angle)

	if abs_angle < 15.0 {
		return ManeuverType.continue_straight
	}
	if abs_angle > 165.0 {
		return ManeuverType.u_turn
	}

	if angle > 0.0 {
		if angle <= 45.0 {
			return ManeuverType.turn_slight_right
		}
		if angle <= 135.0 {
			return ManeuverType.turn_right
		}
		return ManeuverType.turn_sharp_right
	} else {
		neg_angle := -angle
		if neg_angle <= 45.0 {
			return ManeuverType.turn_slight_left
		}
		if neg_angle <= 135.0 {
			return ManeuverType.turn_left
		}
		return ManeuverType.turn_sharp_left
	}
}

// synthesize_instruction produces natural language guidance text.
fn synthesize_instruction(maneuver ManeuverType, street string) string {
	target_name := if street.len > 0 { street } else { 'the road' }
	return match maneuver {
		.depart { 'Depart on ${target_name}' }
		.arrive { 'Arrive at destination on ${target_name}' }
		.continue_straight { 'Continue straight onto ${target_name}' }
		.turn_slight_right { 'Bear slightly right onto ${target_name}' }
		.turn_right { 'Turn right onto ${target_name}' }
		.turn_sharp_right { 'Turn sharp right onto ${target_name}' }
		.turn_slight_left { 'Bear slightly left onto ${target_name}' }
		.turn_left { 'Turn left onto ${target_name}' }
		.turn_sharp_left { 'Turn sharp left onto ${target_name}' }
		.u_turn { 'Make a U-turn onto ${target_name}' }
		.fork_left { 'Keep left at the fork onto ${target_name}' }
		.fork_right { 'Keep right at the fork onto ${target_name}' }
		.roundabout_exit { 'Take the exit onto ${target_name}' }
	}
}
