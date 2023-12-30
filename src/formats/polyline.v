module formats

import core
import math
import strings

// encode_polyline converts an array of coordinates into Google Encoded Polyline string (5-decimal precision).
pub fn encode_polyline(points []core.Coord) string {
	return encode_polyline_custom(points, 1e5)
}

// encode_polyline6 converts an array of coordinates with 6-decimal (~10cm) high precision.
pub fn encode_polyline6(points []core.Coord) string {
	return encode_polyline_custom(points, 1e6)
}

fn encode_polyline_custom(points []core.Coord, factor f64) string {
	mut sb := strings.new_builder(points.len * 4)
	mut prev_lat := i32(0)
	mut prev_lon := i32(0)

	for pt in points {
		curr_lat := i32(math.round(pt.lat * factor))
		curr_lon := i32(math.round(pt.lon * factor))

		d_lat := curr_lat - prev_lat
		d_lon := curr_lon - prev_lon

		prev_lat = curr_lat
		prev_lon = curr_lon

		encode_signed_number(d_lat, mut sb)
		encode_signed_number(d_lon, mut sb)
	}

	return sb.str()
}

// decode_polyline parses a Google Encoded Polyline string back into coordinates.
pub fn decode_polyline(encoded string) []core.Coord {
	return decode_polyline_custom(encoded, 1e5)
}

// decode_polyline6 parses a 6-decimal Google Encoded Polyline string back into coordinates.
pub fn decode_polyline6(encoded string) []core.Coord {
	return decode_polyline_custom(encoded, 1e6)
}

fn decode_polyline_custom(encoded string, factor f64) []core.Coord {
	mut points := []core.Coord{}
	bytes := encoded.bytes()
	mut idx := 0
	mut lat := i32(0)
	mut lon := i32(0)

	for idx < bytes.len {
		d_lat := decode_signed_number(bytes, mut idx)
		d_lon := decode_signed_number(bytes, mut idx)

		lat += d_lat
		lon += d_lon

		points << core.Coord{
			lat: f64(lat) / factor
			lon: f64(lon) / factor
		}
	}

	return points
}

fn encode_signed_number(num i32, mut sb strings.Builder) {
	unum := u32(num)
	mut sgn := if num < 0 { ~(unum << 1) } else { unum << 1 }
	for sgn >= 0x20 {
		next_char := u8((0x20 | (sgn & 0x1F)) + 63)
		sb.write_u8(next_char)
		sgn >>= 5
	}
	sb.write_u8(u8(sgn + 63))
}

fn decode_signed_number(bytes []u8, mut idx &int) i32 {
	mut result := u32(0)
	mut shift := u32(0)

	for unsafe { *idx } < bytes.len {
		b := bytes[unsafe { *idx }]
		unsafe {
			*idx = *idx + 1
		}
		val := u32(b - 63)
		result |= (val & 0x1F) << shift
		shift += 5
		if val < 0x20 {
			break
		}
	}

	i_res := i32(result)
	return if (result & 1) != 0 { ~(i_res >> 1) } else { i_res >> 1 }
}
