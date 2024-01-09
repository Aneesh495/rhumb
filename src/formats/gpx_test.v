module formats

import core
import matcher
import math

fn test_gpx_export_and_parse_roundtrip() {
	original := [
		matcher.GPSPoint{
			coord: core.Coord{
				lat: 37.774900, lon: -122.419400
			}
			timestamp_sec: 1000.0
			speed_mps: 15.0
			heading_deg: 90.0
		},
		matcher.GPSPoint{
			coord: core.Coord{
				lat: 37.783300, lon: -122.416700
			}
			timestamp_sec: 1010.0
			speed_mps: 15.0
			heading_deg: 90.0
		},
	]

	xml := export_gpx_track(original, 'San Francisco Commute')
	assert xml.contains('<?xml')
	assert xml.contains('San Francisco Commute')
	assert xml.contains('trkpt')

	parsed := parse_gpx_track(xml) or { panic('gpx parsing failed') }
	assert parsed.len == 2

	assert math.abs(parsed[0].coord.lat - 37.774900) < 1e-5
	assert math.abs(parsed[0].coord.lon - -122.419400) < 1e-5
	assert math.abs(parsed[1].coord.lat - 37.783300) < 1e-5
	assert math.abs(parsed[1].coord.lon - -122.416700) < 1e-5
}
