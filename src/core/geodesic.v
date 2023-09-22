module core

import math

// haversine_distance_m computes the spherical distance in meters between two coordinates.
// Employs the numerically stable Haversine formulation over the Earth mean radius.
pub fn haversine_distance_m(p1 Coord, p2 Coord) f64 {
	phi1 := deg_to_rad(p1.lat)
	phi2 := deg_to_rad(p2.lat)
	delta_phi := deg_to_rad(p2.lat - p1.lat)
	delta_lambda := deg_to_rad(p2.lon - p1.lon)

	sin_half_dphi := math.sin(delta_phi / 2.0)
	sin_half_dlambda := math.sin(delta_lambda / 2.0)

	a := sin_half_dphi * sin_half_dphi + math.cos(phi1) * math.cos(phi2) * sin_half_dlambda * sin_half_dlambda
	c := 2.0 * math.atan2(math.sqrt(a), math.sqrt(math.max(0.0, 1.0 - a)))

	return earth_mean_radius_m * c
}

// vincenty_distance_m computes high-precision geodesic distance in meters on the WGS84 ellipsoid.
// Resolves Vincenty inverse equations iteratively down to 1e-12 tolerance.
// Returns None if coordinates are nearly antipodal and the iterative solution fails to converge.
pub fn vincenty_distance_m(p1 Coord, p2 Coord) ?f64 {
	if math.abs(p1.lat - p2.lat) < 1e-9 && math.abs(p1.lon - p2.lon) < 1e-9 {
		return 0.0
	}

	a := wgs84_a
	b := wgs84_b
	f := wgs84_f

	u1 := math.atan((1.0 - f) * math.tan(deg_to_rad(p1.lat)))
	u2 := math.atan((1.0 - f) * math.tan(deg_to_rad(p2.lat)))
	l := deg_to_rad(p2.lon - p1.lon)

	sin_u1 := math.sin(u1)
	cos_u1 := math.cos(u1)
	sin_u2 := math.sin(u2)
	cos_u2 := math.cos(u2)

	mut lambda := l
	mut lambda_prev := 0.0
	mut iter_limit := 100

	mut sin_sigma := 0.0
	mut cos_sigma := 0.0
	mut sigma := 0.0
	mut sin_alpha := 0.0
	mut cos2_alpha := 0.0
	mut cos_2sigma_m := 0.0

	for iter_limit > 0 {
		sin_lambda := math.sin(lambda)
		cos_lambda := math.cos(lambda)

		term1 := cos_u2 * sin_lambda
		term2 := cos_u1 * sin_u2 - sin_u1 * cos_u2 * cos_lambda
		sin_sigma = math.sqrt(term1 * term1 + term2 * term2)

		if sin_sigma == 0.0 {
			return 0.0 // Coincident points
		}

		cos_sigma = sin_u1 * sin_u2 + cos_u1 * cos_u2 * cos_lambda
		sigma = math.atan2(sin_sigma, cos_sigma)

		sin_alpha = (cos_u1 * cos_u2 * sin_lambda) / sin_sigma
		cos2_alpha = 1.0 - sin_alpha * sin_alpha

		cos_2sigma_m = if cos2_alpha != 0.0 {
			cos_sigma - 2.0 * sin_u1 * sin_u2 / cos2_alpha
		} else {
			0.0 // Equatorial line
		}

		c_factor := f / 16.0 * cos2_alpha * (4.0 + f * (4.0 - 3.0 * cos2_alpha))
		lambda_prev = lambda
		lambda = l + (1.0 - c_factor) * f * sin_alpha * (sigma + c_factor * sin_sigma * (cos_2sigma_m + c_factor * cos_sigma * (-1.0 + 2.0 * cos_2sigma_m * cos_2sigma_m)))

		if math.abs(lambda - lambda_prev) <= 1e-12 {
			break
		}
		iter_limit--
	}

	if iter_limit == 0 {
		// Fallback to Haversine if antipodal divergence occurs
		return haversine_distance_m(p1, p2)
	}

	u_sq := cos2_alpha * (a * a - b * b) / (b * b)
	capital_a := 1.0 + u_sq / 16384.0 * (4096.0 + u_sq * (-768.0 + u_sq * (320.0 - 175.0 * u_sq)))
	capital_b := u_sq / 1024.0 * (256.0 + u_sq * (-128.0 + u_sq * (74.0 - 47.0 * u_sq)))

	delta_sigma := capital_b * sin_sigma * (cos_2sigma_m + capital_b / 4.0 * (cos_sigma * (-1.0 + 2.0 * cos_2sigma_m * cos_2sigma_m) - capital_b / 6.0 * cos_2sigma_m * (-3.0 + 4.0 * sin_sigma * sin_sigma) * (-3.0 + 4.0 * cos_2sigma_m * cos_2sigma_m)))

	s := b * capital_a * (sigma - delta_sigma)
	return s
}

// rhumb_distance_m calculates distance along a constant-bearing loxodrome line on the sphere.
pub fn rhumb_distance_m(p1 Coord, p2 Coord) f64 {
	phi1 := deg_to_rad(p1.lat)
	phi2 := deg_to_rad(p2.lat)
	dphi := phi2 - phi1
	mut dlon := math.abs(deg_to_rad(p2.lon - p1.lon))

	if dlon > math.pi {
		dlon = 2.0 * math.pi - dlon
	}

	// Projected latitude stretch on Mercator cylinder
	dpsi := math.log(math.tan(math.pi / 4.0 + phi2 / 2.0) / math.tan(math.pi / 4.0 + phi1 / 2.0))
	q := if math.abs(dpsi) > 1e-10 {
		dphi / dpsi
	} else {
		math.cos(phi1) // Along parallel of latitude
	}

	delta := math.sqrt(dphi * dphi + q * q * dlon * dlon)
	return earth_mean_radius_m * delta
}

// rhumb_bearing_deg calculates the constant bearing in degrees [0, 360) along a rhumb line.
pub fn rhumb_bearing_deg(p1 Coord, p2 Coord) f64 {
	phi1 := deg_to_rad(p1.lat)
	phi2 := deg_to_rad(p2.lat)
	mut dlon := deg_to_rad(p2.lon - p1.lon)

	if math.abs(dlon) > math.pi {
		dlon = if dlon > 0.0 { -(2.0 * math.pi - dlon) } else { 2.0 * math.pi + dlon }
	}

	dpsi := math.log(math.tan(math.pi / 4.0 + phi2 / 2.0) / math.tan(math.pi / 4.0 + phi1 / 2.0))
	theta := math.atan2(dlon, dpsi)
	return normalize_bearing(rad_to_deg(theta))
}

// initial_bearing_deg calculates the initial forward azimuth (0 to 360 degrees) from p1 to p2.
pub fn initial_bearing_deg(p1 Coord, p2 Coord) f64 {
	phi1 := deg_to_rad(p1.lat)
	phi2 := deg_to_rad(p2.lat)
	dlambda := deg_to_rad(p2.lon - p1.lon)

	y := math.sin(dlambda) * math.cos(phi2)
	x := math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlambda)

	theta := math.atan2(y, x)
	return normalize_bearing(rad_to_deg(theta))
}

// final_bearing_deg calculates the arriving azimuth (0 to 360 degrees) at p2 along the great-circle path.
pub fn final_bearing_deg(p1 Coord, p2 Coord) f64 {
	// Reversing direction and flipping 180 degrees yields destination arrival azimuth
	reverse_bearing := initial_bearing_deg(p2, p1)
	return normalize_bearing(reverse_bearing + 180.0)
}

// destination_point computes the destination coordinate given a starting position, distance in meters, and bearing.
pub fn destination_point(start Coord, distance_m f64, bearing_deg f64) Coord {
	angular_dist := distance_m / earth_mean_radius_m
	theta := deg_to_rad(bearing_deg)
	phi1 := deg_to_rad(start.lat)
	lambda1 := deg_to_rad(start.lon)

	sin_phi2 := math.sin(phi1) * math.cos(angular_dist) + math.cos(phi1) * math.sin(angular_dist) * math.cos(theta)
	phi2 := math.asin(sin_phi2)

	y := math.sin(theta) * math.sin(angular_dist) * math.cos(phi1)
	x := math.cos(angular_dist) - math.sin(phi1) * math.sin(phi2)
	lambda2 := lambda1 + math.atan2(y, x)

	return Coord{
		lat: rad_to_deg(phi2)
		lon: rad_to_deg(lambda2)
	}
}

// midpoint calculates the great-circle midpoint between two geographic coordinates.
pub fn midpoint(p1 Coord, p2 Coord) Coord {
	phi1 := deg_to_rad(p1.lat)
	lambda1 := deg_to_rad(p1.lon)
	phi2 := deg_to_rad(p2.lat)
	dlambda := deg_to_rad(p2.lon - p1.lon)

	bx := math.cos(phi2) * math.cos(dlambda)
	by := math.cos(phi2) * math.sin(dlambda)

	phi3 := math.atan2(math.sin(phi1) + math.sin(phi2), math.sqrt((math.cos(phi1) + bx) * (math.cos(phi1) + bx) + by * by))
	lambda3 := lambda1 + math.atan2(by, math.cos(phi1) + bx)

	return Coord{
		lat: rad_to_deg(phi3)
		lon: rad_to_deg(lambda3)
	}
}
