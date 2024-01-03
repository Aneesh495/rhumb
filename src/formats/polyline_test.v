module formats

import core
import math

fn test_google_polyline_roundtrip() {
	// Google official polyline test vector:
	// Points: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
	// Encoded string: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
	points := [
		core.Coord{
			lat: 38.5, lon: -120.2
		},
		core.Coord{
			lat: 40.7, lon: -120.95
		},
		core.Coord{
			lat: 43.252, lon: -126.453
		},
	]

	encoded := encode_polyline(points)
	assert encoded == '_p~iF~ps|U_ulLnnqC_mqNvxq`@'

	decoded := decode_polyline(encoded)
	assert decoded.len == 3
	for i in 0 .. 3 {
		assert math.abs(decoded[i].lat - points[i].lat) < 1e-5
		assert math.abs(decoded[i].lon - points[i].lon) < 1e-5
	}
}

fn test_polyline6_high_precision_roundtrip() {
	points := [
		core.Coord{
			lat: 37.774929, lon: -122.419416
		},
		core.Coord{
			lat: 37.783333, lon: -122.416667
		},
	]

	encoded := encode_polyline6(points)
	decoded := decode_polyline6(encoded)

	assert decoded.len == 2
	for i in 0 .. 2 {
		assert math.abs(decoded[i].lat - points[i].lat) < 1e-6
		assert math.abs(decoded[i].lon - points[i].lon) < 1e-6
	}
}
