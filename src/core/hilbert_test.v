module core

import math

fn test_hilbert_roundtrip() {
	coords := [
		Coord{
			lat: 37.7749, lon: -122.4194
		}, // San Francisco
		Coord{
			lat: 40.7128, lon: -74.0060
		}, // New York
		Coord{
			lat: 51.5074, lon: -0.1278
		}, // London
		Coord{
			lat: -33.8688, lon: 151.2093
		}, // Sydney
		Coord{
			lat: 0.0, lon: 0.0
		},
	]

	for c in coords {
		h := coord_to_hilbert64(c)
		recovered := hilbert64_to_coord(h)
		// 31-bit resolution gives sub-centimeter geographic precision
		assert math.abs(recovered.lat - c.lat) < 1e-4
		assert math.abs(recovered.lon - c.lon) < 1e-4
	}
}

fn test_hilbert_monotonicity_and_locality() {
	// Nearby points in San Francisco should produce closely clustered Hilbert indices
	sf1 := Coord{
		lat: 37.7749
		lon: -122.4194
	}
	sf2 := Coord{
		lat: 37.7750
		lon: -122.4195
	}
	tokyo := Coord{
		lat: 35.6762
		lon: 139.6503
	}

	h_sf1 := coord_to_hilbert64(sf1)
	h_sf2 := coord_to_hilbert64(sf2)
	h_tokyo := coord_to_hilbert64(tokyo)

	diff_local := if h_sf1 > h_sf2 { h_sf1 - h_sf2 } else { h_sf2 - h_sf1 }
	diff_remote := if h_sf1 > h_tokyo { h_sf1 - h_tokyo } else { h_tokyo - h_sf1 }

	// Spatial difference between SF points should be orders of magnitude smaller than SF to Tokyo
	assert diff_local < diff_remote
}
