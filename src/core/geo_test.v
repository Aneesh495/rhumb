module core

import math

fn test_coord_validation() {
	valid_sf := Coord{
		lat: 37.7749
		lon: -122.4194
	}
	assert valid_sf.is_valid()

	invalid_lat := Coord{
		lat: 91.0
		lon: 0.0
	}
	assert !invalid_lat.is_valid()

	invalid_lon := Coord{
		lat: 0.0
		lon: -181.0
	}
	assert !invalid_lon.is_valid()
}

fn test_ecef_roundtrip() {
	points := [
		Coord3D{
			lat: 37.7749
			lon: -122.4194
			ele: 15.0
		}, // San Francisco
		Coord3D{
			lat: 51.5074
			lon: -0.1278
			ele: 25.0
		}, // London
		Coord3D{
			lat: 35.6762
			lon: 139.6503
			ele: 40.0
		}, // Tokyo
		Coord3D{
			lat: 0.0
			lon: 0.0
			ele: 0.0
		}, // Prime meridian equator
		Coord3D{
			lat: 90.0
			lon: 0.0
			ele: 100.0
		}, // North pole
	]

	for pt in points {
		ecef := to_ecef(pt)
		recovered := from_ecef(ecef)
		assert math.abs(recovered.lat - pt.lat) < 1e-6
		if pt.lat < 89.9 {
			assert math.abs(recovered.lon - pt.lon) < 1e-6
		}
		assert math.abs(recovered.ele - pt.ele) < 1e-3
	}
}

fn test_web_mercator_roundtrip() {
	coords := [
		Coord{
			lat: 37.7749
			lon: -122.4194
		},
		Coord{
			lat: 40.7128
			lon: -74.0060
		},
		Coord{
			lat: -33.8688
			lon: 151.2093
		}, // Sydney
	]

	for c in coords {
		merc := to_web_mercator(c)
		unprojected := from_web_mercator(merc)
		assert math.abs(unprojected.lat - c.lat) < 1e-7
		assert math.abs(unprojected.lon - c.lon) < 1e-7
	}
}

fn test_haversine_and_vincenty_distances() {
	sf := Coord{
		lat: 37.7749
		lon: -122.4194
	}
	nyc := Coord{
		lat: 40.7128
		lon: -74.0060
	}

	dist_haversine := haversine_distance_m(sf, nyc)
	dist_vincenty := vincenty_distance_m(sf, nyc) or { 0.0 }

	// San Francisco to NYC is approximately 4,130 km
	assert dist_haversine > 4100000.0 && dist_haversine < 4200000.0
	assert dist_vincenty > 4100000.0 && dist_vincenty < 4200000.0

	// Ellipsoidal vs spherical model should agree within 0.5%
	discrepancy_ratio := math.abs(dist_haversine - dist_vincenty) / dist_vincenty
	assert discrepancy_ratio < 0.005

	// Coincident points must yield zero
	assert haversine_distance_m(sf, sf) == 0.0
	assert (vincenty_distance_m(sf, sf) or { 1.0 }) == 0.0
}

fn test_rhumb_distance_and_bearings() {
	p1 := Coord{
		lat: 50.0
		lon: -5.0
	}
	p2 := Coord{
		lat: 58.0
		lon: 3.0
	}

	rhumb_d := rhumb_distance_m(p1, p2)
	rhumb_b := rhumb_bearing_deg(p1, p2)

	assert rhumb_d > 900000.0 && rhumb_d < 1200000.0
	assert rhumb_b >= 0.0 && rhumb_b <= 360.0

	// Initial bearing from London to Paris is roughly 148 degrees
	london := Coord{
		lat: 51.5074
		lon: -0.1278
	}
	paris := Coord{
		lat: 48.8566
		lon: 2.3522
	}

	bearing := initial_bearing_deg(london, paris)
	assert bearing > 140.0 && bearing < 160.0

	final_b := final_bearing_deg(london, paris)
	assert final_b > 140.0 && final_b < 160.0
}

fn test_destination_and_midpoint() {
	start := Coord{
		lat: 37.7749
		lon: -122.4194
	}
	distance := 50000.0 // 50 km
	bearing := 90.0 // Due east

	dest := destination_point(start, distance, bearing)
	assert dest.lat > 37.0 && dest.lat < 38.5
	assert dest.lon > -122.4194 // Longitude should move east

	measured := haversine_distance_m(start, dest)
	assert math.abs(measured - distance) < 10.0 // Within 10m

	mid := midpoint(start, dest)
	dist_to_mid := haversine_distance_m(start, mid)
	assert math.abs(dist_to_mid - distance / 2.0) < 5.0
}
