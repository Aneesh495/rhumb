module formats

import core
import matcher
import strings

// export_gpx_track serializes GPS points into a standard GPX 1.1 XML document.
pub fn export_gpx_track(points []matcher.GPSPoint, track_name string) string {
	mut sb := strings.new_builder(points.len * 128)
	sb.writeln('<?xml version="1.0" encoding="UTF-8"?>')
	sb.writeln('<gpx version="1.1" creator="rhumb-engine" xmlns="http://www.topografix.com/GPX/1/1">')
	sb.writeln('  <trk>')
	sb.writeln('    <name>${track_name}</name>')
	sb.writeln('    <trkseg>')

	for pt in points {
		sb.write_string('      <trkpt lat="${pt.coord.lat:.6f}" lon="${pt.coord.lon:.6f}">')
		if pt.speed_mps > 0.0 {
			sb.write_string('<speed>${pt.speed_mps:.2f}</speed>')
		}
		sb.writeln('</trkpt>')
	}

	sb.writeln('    </trkseg>')
	sb.writeln('  </trk>')
	sb.writeln('</gpx>')

	return sb.str()
}

// parse_gpx_track extracts GPS track points from GPX 1.1 XML content.
pub fn parse_gpx_track(raw_xml string) ?[]matcher.GPSPoint {
	mut points := []matcher.GPSPoint{}
	lines := raw_xml.split_into_lines()

	for line in lines {
		if line.contains('<trkpt') {
			lat_str := extract_attr(line, 'lat') or { continue }
			lon_str := extract_attr(line, 'lon') or { continue }

			lat := lat_str.f64()
			lon := lon_str.f64()

			points << matcher.GPSPoint{
				coord: core.Coord{
					lat: lat
					lon: lon
				}
				timestamp_sec: 0.0
				speed_mps: 0.0
				heading_deg: 0.0
			}
		}
	}

	return points
}

// extract_attr extracts attribute value from an XML tag string like attr="value".
fn extract_attr(line string, attr string) ?string {
	key := '${attr}="'
	start_idx := line.index(key) or { return none }
	val_start := start_idx + key.len
	val_end := line[val_start..].index('"') or { return none }
	return line[val_start..val_start + val_end]
}
