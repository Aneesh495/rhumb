module tiles

import core
import math

// tile_bounds computes the WGS84 bounding box corresponding to tile coordinates (z, x, y).
pub fn tile_bounds(z int, x int, y int) core.BBox2D {
	n := math.pow(2.0, f64(z))

	lon_min := f64(x) / n * 360.0 - 180.0
	lon_max := f64(x + 1) / n * 360.0 - 180.0

	lat_max := tile_y_to_lat(y, z)
	lat_min := tile_y_to_lat(y + 1, z)

	return core.new_bbox2d(lat_min, lon_min, lat_max, lon_max)
}

// coord_to_tile converts a WGS84 geographic coordinate into tile indices (x, y) at zoom level z.
pub fn coord_to_tile(c core.Coord, z int) (int, int) {
	n := math.pow(2.0, f64(z))
	clamped_lat := math.clamp(c.lat, -85.05112877980659, 85.05112877980659)

	x := int(math.floor((c.lon + 180.0) / 360.0 * n))

	lat_rad := core.deg_to_rad(clamped_lat)
	y := int(math.floor((1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n))

	max_idx := int(n) - 1
	clamped_x := if x < 0 { 0 } else if x > max_idx { max_idx } else { x }
	clamped_y := if y < 0 { 0 } else if y > max_idx { max_idx } else { y }
	return clamped_x, clamped_y
}

// tile_y_to_lat converts a vertical slippy map tile index to northern WGS84 latitude.
fn tile_y_to_lat(y int, z int) f64 {
	n := math.pow(2.0, f64(z))
	sinh_val := math.sinh(math.pi * (1.0 - 2.0 * f64(y) / n))
	return core.rad_to_deg(math.atan(sinh_val))
}
