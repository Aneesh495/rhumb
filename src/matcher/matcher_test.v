module matcher

import core
import graph
import math
import routing

fn test_hmm_probability_distributions() {
	// Emission: distance 0 should have higher log-probability than distance 20m
	p0 := emission_log_probability(0.0, default_sigma_z)
	p20 := emission_log_probability(20.0, default_sigma_z)
	assert p0 > p20

	// Transition: small discrepancy (0m) should have higher log-prob than large discrepancy (50m)
	t0 := transition_log_probability(100.0, 100.0, default_beta)
	t50 := transition_log_probability(100.0, 150.0, default_beta)
	assert t0 > t50
}

fn test_map_matcher_noisy_trajectory() {
	// Construct a 2-segment straight roadway in San Francisco
	mut builder := graph.new_graph_builder()
	n0 := builder.add_node(1, core.Coord{
		lat: 37.7749, lon: -122.4200
	}, 0.0)
	n1 := builder.add_node(2, core.Coord{
		lat: 37.7749, lon: -122.4150
	}, 0.0)
	n2 := builder.add_node(3, core.Coord{
		lat: 37.7749, lon: -122.4100
	}, 0.0)

	builder.add_edge(n0, n1, 400.0, 50.0, graph.HighwayClass.primary, graph.access_car,
		graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Market St', []core.Coord{})
	builder.add_edge(n1, n2, 400.0, 50.0, graph.HighwayClass.primary, graph.access_car,
		graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Market St', []core.Coord{})

	g := builder.build()
	car := graph.car_profile()
	_ = routing.max_network_speed_mps

	// Generate synthetic noisy trajectory simulating GPS jitter (+- 10 meters north of road)
	trajectory := [
		GPSPoint{
			coord: core.Coord{
				lat: 37.7750, lon: -122.4190
			} // ~11m north
			timestamp_sec: 1000.0
			speed_mps: 12.0
			heading_deg: 90.0
		},
		GPSPoint{
			coord: core.Coord{
				lat: 37.7748, lon: -122.4160
			} // ~11m south
			timestamp_sec: 1010.0
			speed_mps: 12.0
			heading_deg: 90.0
		},
		GPSPoint{
			coord: core.Coord{
				lat: 37.7751, lon: -122.4130
			} // ~20m north
			timestamp_sec: 1020.0
			speed_mps: 12.0
			heading_deg: 90.0
		},
		GPSPoint{
			coord: core.Coord{
				lat: 37.7749, lon: -122.4105
			} // ~0m error
			timestamp_sec: 1030.0
			speed_mps: 12.0
			heading_deg: 90.0
		},
	]

	matcher := new_map_matcher()
	result := matcher.match_trajectory(&g, trajectory, car) or { panic('map match failed') }

	assert result.matched_points.len == 4
	assert result.matched_edges.len >= 1
	assert result.average_confidence > 0.5

	// All matched points should be snapped tightly onto latitude 37.7749 of the road
	for pt in result.matched_points {
		assert pt.distance_m < 30.0
		assert math.abs(pt.matched_coord.lat - 37.7749) < 1e-4
	}
}
