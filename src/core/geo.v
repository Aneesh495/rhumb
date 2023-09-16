module core

import math

// WGS84 ellipsoid parameters defined by EPSG:7030 / IERS numerical standards.
pub const wgs84_a = 6378137.0 // Semi-major axis in meters
pub const wgs84_b = 6356752.314245179 // Semi-minor axis in meters
pub const wgs84_f = 1.0 / 298.257223563 // Flattening factor
pub const wgs84_e2 = 6.69437999014e-3 // First eccentricity squared: f * (2.0 - f)
pub const earth_mean_radius_m = 6371008.8 // Volumetric mean radius in meters

// Coord represents a 2D geographic coordinate on the WGS84 datum.
// Latitude ranges from -90.0 to +90.0 degrees; longitude ranges from -180.0 to +180.0 degrees.
pub struct Coord {
pub:
	lat f64
	lon f64
}

// Coord3D represents a 3D geographic point with ellipsoidal elevation in meters.
pub struct Coord3D {
pub:
	lat f64
	lon f64
	ele f64
}

// ECEF represents Earth-Centered, Earth-Fixed Cartesian coordinates in meters.
pub struct ECEF {
pub:
	x f64
	y f64
	z f64
}

// MercatorPoint represents projected planar coordinates in Spherical Web Mercator (EPSG:3857).
pub struct MercatorPoint {
pub:
	x f64
	y f64
}

// is_valid verifies that latitude and longitude conform to standard spherical bounds.
pub fn (c Coord) is_valid() bool {
	return c.lat >= -90.0 && c.lat <= 90.0 && c.lon >= -180.0 && c.lon <= 180.0
}

// to_coord2d drops elevation to yield a standard 2D coordinate.
pub fn (c Coord3D) to_coord2d() Coord {
	return Coord{
		lat: c.lat
		lon: c.lon
	}
}

// deg_to_rad converts degrees to radians.
[inline]
pub fn deg_to_rad(deg f64) f64 {
	return deg * math.pi / 180.0
}

// rad_to_deg converts radians to degrees.
[inline]
pub fn rad_to_deg(rad f64) f64 {
	return rad * 180.0 / math.pi
}

// normalize_bearing wraps an angle in degrees into the standard [0, 360) azimuth range.
pub fn normalize_bearing(deg f64) f64 {
	mut b := math.fmod(deg, 360.0)
	if b < 0.0 {
		b += 360.0
	}
	return b
}

// to_ecef transforms WGS84 geographic coordinates with ellipsoidal height to ECEF coordinates.
pub fn to_ecef(c Coord3D) ECEF {
	phi := deg_to_rad(c.lat)
	lambda := deg_to_rad(c.lon)
	sin_phi := math.sin(phi)
	cos_phi := math.cos(phi)
	sin_lambda := math.sin(lambda)
	cos_lambda := math.cos(lambda)

	// Prime vertical radius of curvature N(phi)
	n := wgs84_a / math.sqrt(1.0 - wgs84_e2 * sin_phi * sin_phi)

	return ECEF{
		x: (n + c.ele) * cos_phi * cos_lambda
		y: (n + c.ele) * cos_phi * sin_lambda
		z: (n * (1.0 - wgs84_e2) + c.ele) * sin_phi
	}
}

// from_ecef transforms Cartesian ECEF coordinates back into WGS84 using Bowring's method.
pub fn from_ecef(e ECEF) Coord3D {
	p := math.sqrt(e.x * e.x + e.y * e.y)
	if p < 1e-6 {
		// Polar singularity handling
		lat := if e.z > 0.0 { 90.0 } else { -90.0 }
		ele := math.abs(e.z) - wgs84_b
		return Coord3D{
			lat: lat
			lon: 0.0
			ele: ele
		}
	}

	// Bowring closed-form iterative refinement
	b := wgs84_b
	e2_prime := (wgs84_a * wgs84_a - b * b) / (b * b)
	theta := math.atan2(e.z * wgs84_a, p * b)
	sin_theta := math.sin(theta)
	cos_theta := math.cos(theta)

	phi := math.atan2(e.z + e2_prime * b * sin_theta * sin_theta * sin_theta, p - wgs84_e2 * wgs84_a * cos_theta * cos_theta * cos_theta)
	lambda := math.atan2(e.y, e.x)

	sin_phi := math.sin(phi)
	n := wgs84_a / math.sqrt(1.0 - wgs84_e2 * sin_phi * sin_phi)
	ele := p / math.cos(phi) - n

	return Coord3D{
		lat: rad_to_deg(phi)
		lon: rad_to_deg(lambda)
		ele: ele
	}
}

// to_web_mercator projects WGS84 coordinates into EPSG:3857 coordinates.
pub fn to_web_mercator(c Coord) MercatorPoint {
	// Clip latitude to Web Mercator projection bounds (~85.05112878 degrees)
	clipped_lat := math.clamp(c.lat, -85.05112877980659, 85.05112877980659)
	x := c.lon * 20037508.342789244 / 180.0
	rad := deg_to_rad(clipped_lat)
	y := math.log(math.tan(math.pi / 4.0 + rad / 2.0)) * 20037508.342789244 / math.pi
	return MercatorPoint{
		x: x
		y: y
	}
}

// from_web_mercator unprojects EPSG:3857 planar coordinates back to WGS84 geographic coordinates.
pub fn from_web_mercator(m MercatorPoint) Coord {
	lon := m.x * 180.0 / 20037508.342789244
	lat_rad := math.pi / 2.0 - 2.0 * math.atan(math.exp(-m.y * math.pi / 20037508.342789244))
	return Coord{
		lat: rad_to_deg(lat_rad)
		lon: lon
	}
}
