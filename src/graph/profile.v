module graph

import math

// VehicleProfile dictates routing behavior, traversal cost formulas, and turn penalties.
pub struct VehicleProfile {
pub:
	name                      string
	default_speeds            map[HighwayClass]f32
	access_mask               u8
	turn_penalty_ms           u32
	u_turn_penalty_ms         u32
	traffic_signal_penalty_ms u32
	surface_factors           map[SurfaceType]f32
	elevation_penalty_factor  f32
}

// car_profile configures routing physics for standard passenger automobiles.
pub fn car_profile() VehicleProfile {
	mut speeds := map[HighwayClass]f32{}
	speeds[HighwayClass.motorway] = 110.0
	speeds[HighwayClass.trunk] = 90.0
	speeds[HighwayClass.primary] = 70.0
	speeds[HighwayClass.secondary] = 50.0
	speeds[HighwayClass.tertiary] = 40.0
	speeds[HighwayClass.residential] = 30.0
	speeds[HighwayClass.service] = 15.0
	speeds[HighwayClass.motorway_link] = 60.0
	speeds[HighwayClass.trunk_link] = 50.0
	speeds[HighwayClass.primary_link] = 40.0
	speeds[HighwayClass.secondary_link] = 30.0
	speeds[HighwayClass.tertiary_link] = 25.0
	speeds[HighwayClass.living_street] = 10.0
	speeds[HighwayClass.unclassified] = 30.0

	mut surfaces := map[SurfaceType]f32{}
	surfaces[SurfaceType.paved] = 1.0
	surfaces[SurfaceType.asphalt] = 1.0
	surfaces[SurfaceType.concrete] = 1.0
	surfaces[SurfaceType.gravel] = 0.6
	surfaces[SurfaceType.dirt] = 0.4
	surfaces[SurfaceType.unpaved] = 0.5
	surfaces[SurfaceType.cobblestone] = 0.5

	return VehicleProfile{
		name: 'car'
		default_speeds: speeds
		access_mask: access_car
		turn_penalty_ms: 1500 // 1.5 second junction delay
		u_turn_penalty_ms: 10000 // 10 second U-turn delay
		traffic_signal_penalty_ms: 3000
		surface_factors: surfaces
		elevation_penalty_factor: 0.05
	}
}

// bike_profile configures routing preferences for bicycles.
pub fn bike_profile() VehicleProfile {
	mut speeds := map[HighwayClass]f32{}
	speeds[HighwayClass.cycleway] = 20.0
	speeds[HighwayClass.path] = 15.0
	speeds[HighwayClass.living_street] = 15.0
	speeds[HighwayClass.residential] = 18.0
	speeds[HighwayClass.tertiary] = 16.0
	speeds[HighwayClass.secondary] = 14.0
	speeds[HighwayClass.primary] = 10.0 // Arterials penalized for safety
	speeds[HighwayClass.unclassified] = 15.0
	speeds[HighwayClass.service] = 12.0

	mut surfaces := map[SurfaceType]f32{}
	surfaces[SurfaceType.paved] = 1.0
	surfaces[SurfaceType.asphalt] = 1.0
	surfaces[SurfaceType.concrete] = 0.95
	surfaces[SurfaceType.gravel] = 0.5
	surfaces[SurfaceType.dirt] = 0.3
	surfaces[SurfaceType.unpaved] = 0.4
	surfaces[SurfaceType.cobblestone] = 0.4

	return VehicleProfile{
		name: 'bicycle'
		default_speeds: speeds
		access_mask: access_bike
		turn_penalty_ms: 500
		u_turn_penalty_ms: 2000
		traffic_signal_penalty_ms: 1000
		surface_factors: surfaces
		elevation_penalty_factor: 0.5 // High penalty for uphill climbs
	}
}

// foot_profile configures pedestrian walking routing.
pub fn foot_profile() VehicleProfile {
	mut speeds := map[HighwayClass]f32{}
	speeds[HighwayClass.footway] = 5.0
	speeds[HighwayClass.path] = 4.5
	speeds[HighwayClass.pedestrian] = 5.0
	speeds[HighwayClass.living_street] = 5.0
	speeds[HighwayClass.residential] = 4.5
	speeds[HighwayClass.service] = 4.0
	speeds[HighwayClass.tertiary] = 3.5
	speeds[HighwayClass.secondary] = 3.0
	speeds[HighwayClass.unclassified] = 4.0

	mut surfaces := map[SurfaceType]f32{}
	surfaces[SurfaceType.paved] = 1.0
	surfaces[SurfaceType.asphalt] = 1.0
	surfaces[SurfaceType.concrete] = 1.0
	surfaces[SurfaceType.gravel] = 0.8
	surfaces[SurfaceType.dirt] = 0.7
	surfaces[SurfaceType.unpaved] = 0.75
	surfaces[SurfaceType.cobblestone] = 0.9

	return VehicleProfile{
		name: 'foot'
		default_speeds: speeds
		access_mask: access_foot
		turn_penalty_ms: 0
		u_turn_penalty_ms: 0
		traffic_signal_penalty_ms: 500
		surface_factors: surfaces
		elevation_penalty_factor: 0.8 // Steep slopes slow walking
	}
}

// compute_traversal_ms calculates edge traversal time in milliseconds for the given profile.
pub fn (p VehicleProfile) compute_traversal_ms(edge EdgeAttribute) u32 {
	// Check access permissions
	if (edge.access & p.access_mask) == 0 {
		return infinity_weight // Impassable
	}

	mut speed_kph := if edge.speed_kph > 0.0 {
		edge.speed_kph
	} else if edge.highway in p.default_speeds {
		p.default_speeds[edge.highway]
	} else {
		20.0
	}

	// Apply surface penalty
	if edge.surface in p.surface_factors {
		speed_kph *= p.surface_factors[edge.surface]
	}

	if speed_kph < 1.0 {
		speed_kph = 1.0
	}

	speed_mps := f64(speed_kph) * 1000.0 / 3600.0
	seconds := edge.length_m / speed_mps
	ms := u32(math.max(1.0, seconds * 1000.0))

	return ms
}
