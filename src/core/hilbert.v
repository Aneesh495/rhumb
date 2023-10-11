module core

import math

// hilbert_order defines the 28-bit resolution per dimension, fitting 56 bits into a 64-bit unsigned integer.
// 28-bit resolution yields sub-meter geographic accuracy across the entire globe.
pub const hilbert_order = 28
pub const hilbert_max_coord = u32(1 << hilbert_order) // 2^28 = 268,435,456

// coord_to_hilbert64 converts WGS84 geographic coordinate into a 64-bit Hilbert curve index.
pub fn coord_to_hilbert64(c Coord) u64 {
	clamped_lat := math.clamp(c.lat, -90.0, 90.0)
	clamped_lon := math.clamp(c.lon, -180.0, 180.0)

	norm_y := u32((clamped_lat + 90.0) / 180.0 * f64(hilbert_max_coord - 1))
	norm_x := u32((clamped_lon + 180.0) / 360.0 * f64(hilbert_max_coord - 1))

	return xy_to_hilbert64(norm_x, norm_y)
}

// hilbert64_to_coord converts a 64-bit Hilbert curve index back to WGS84 coordinates.
pub fn hilbert64_to_coord(h u64) Coord {
	x, y := hilbert64_to_xy(h)
	lon := (f64(x) / f64(hilbert_max_coord - 1)) * 360.0 - 180.0
	lat := (f64(y) / f64(hilbert_max_coord - 1)) * 180.0 - 90.0

	return Coord{
		lat: lat
		lon: lon
	}
}

// xy_to_hilbert64 maps 28-bit integer grid coordinates (x, y) into a 64-bit linear Hilbert distance.
pub fn xy_to_hilbert64(x u32, y u32) u64 {
	mut d := u64(0)
	mut s := u32(hilbert_max_coord >> 1)
	mut cur_x := x
	mut cur_y := y

	for s > 0 {
		rx := if (cur_x & s) > 0 { u32(1) } else { u32(0) }
		ry := if (cur_y & s) > 0 { u32(1) } else { u32(0) }

		d += u64(s) * u64(s) * u64((3 * rx) ^ ry)
		cur_x, cur_y = rot_hilbert(s, cur_x, cur_y, rx, ry)
		s >>= 1
	}

	return d
}

// hilbert64_to_xy maps a 64-bit linear Hilbert distance back to 28-bit grid coordinates (x, y).
pub fn hilbert64_to_xy(d u64) (u32, u32) {
	mut t := d
	mut x := u32(0)
	mut y := u32(0)
	mut s := u32(1)

	for s < hilbert_max_coord {
		rx := u32(1 & (t / 2))
		ry := u32(1 & (t ^ u64(rx)))

		x, y = rot_hilbert(s, x, y, rx, ry)
		x += s * rx
		y += s * ry

		t /= 4
		s <<= 1
	}

	return x, y
}

// rot_hilbert performs quadrant rotation and reflection for Hilbert space-filling curve.
@[inline]
fn rot_hilbert(n u32, x u32, y u32, rx u32, ry u32) (u32, u32) {
	if ry == 0 {
		mut nx := x
		mut ny := y
		if rx == 1 {
			nx = n - 1 - x
			ny = n - 1 - y
		}
		// Swap x and y
		return ny, nx
	}
	return x, y
}
