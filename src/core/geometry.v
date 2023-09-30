module core

import math

// BBox2D represents a 2D geographic bounding box defined by minimum and maximum latitude and longitude.
pub struct BBox2D {
pub mut:
	min_lat f64
	min_lon f64
	max_lat f64
	max_lon f64
}

// new_bbox2d initializes a bounding box enclosing the provided coordinates.
pub fn new_bbox2d(min_lat f64, min_lon f64, max_lat f64, max_lon f64) BBox2D {
	return BBox2D{
		min_lat: min_lat
		min_lon: min_lon
		max_lat: max_lat
		max_lon: max_lon
	}
}

// from_points constructs a minimal bounding box covering an array of coordinates.
pub fn bbox_from_points(points []Coord) BBox2D {
	if points.len == 0 {
		return BBox2D{}
	}
	mut min_lat := points[0].lat
	mut max_lat := points[0].lat
	mut min_lon := points[0].lon
	mut max_lon := points[0].lon

	for pt in points {
		if pt.lat < min_lat {
			min_lat = pt.lat
		}
		if pt.lat > max_lat {
			max_lat = pt.lat
		}
		if pt.lon < min_lon {
			min_lon = pt.lon
		}
		if pt.lon > max_lon {
			max_lon = pt.lon
		}
	}
	return BBox2D{
		min_lat: min_lat
		min_lon: min_lon
		max_lat: max_lat
		max_lon: max_lon
	}
}

// contains verifies whether a coordinate falls inside the bounding box.
pub fn (b BBox2D) contains(pt Coord) bool {
	return pt.lat >= b.min_lat && pt.lat <= b.max_lat && pt.lon >= b.min_lon && pt.lon <= b.max_lon
}

// intersects evaluates whether two bounding boxes overlap.
pub fn (b BBox2D) intersects(other BBox2D) bool {
	return !(b.max_lat < other.min_lat || b.min_lat > other.max_lat || b.max_lon < other.min_lon
		|| b.min_lon > other.max_lon)
}

// expand extends this bounding box to include another box.
pub fn (mut b BBox2D) expand(other BBox2D) {
	if other.min_lat < b.min_lat {
		b.min_lat = other.min_lat
	}
	if other.max_lat > b.max_lat {
		b.max_lat = other.max_lat
	}
	if other.min_lon < b.min_lon {
		b.min_lon = other.min_lon
	}
	if other.max_lon > b.max_lon {
		b.max_lon = other.max_lon
	}
}

// center returns the geometric midpoint of the bounding box.
pub fn (b BBox2D) center() Coord {
	return Coord{
		lat: (b.min_lat + b.max_lat) / 2.0
		lon: (b.min_lon + b.max_lon) / 2.0
	}
}

// area_degrees returns the rectangular planar area in square degrees.
pub fn (b BBox2D) area_degrees() f64 {
	dlat := math.max(0.0, b.max_lat - b.min_lat)
	dlon := math.max(0.0, b.max_lon - b.min_lon)
	return dlat * dlon
}

// PointProjection encapsulates the orthogonal projection of a point onto a line segment.
pub struct PointProjection {
pub:
	projected_point Coord
	distance_m      f64
	fraction        f64 // Along-track fraction: 0.0 at start, 1.0 at end
}

// project_point_to_segment computes the closest point on segment (a, b) to query point p.
// Calculates along-track fraction t in [0.0, 1.0] and perpendicular distance in meters.
pub fn project_point_to_segment(p Coord, a Coord, b Coord) PointProjection {
	// Planar equirectangular projection centered around latitude of a
	cos_lat := math.cos(deg_to_rad(a.lat))
	ax := a.lon * cos_lat
	ay := a.lat
	bx := b.lon * cos_lat
	by := b.lat
	px := p.lon * cos_lat
	py := p.lat

	dx := bx - ax
	dy := by - ay
	seg_len_sq := dx * dx + dy * dy

	if seg_len_sq < 1e-14 {
		// Degenerate segment: a and b are identical
		dist := haversine_distance_m(p, a)
		return PointProjection{
			projected_point: a
			distance_m: dist
			fraction: 0.0
		}
	}

	// Unclamped projection parameter t
	t := ((px - ax) * dx + (py - ay) * dy) / seg_len_sq
	clamped_t := math.clamp(t, 0.0, 1.0)

	proj_lon := (ax + clamped_t * dx) / cos_lat
	proj_lat := ay + clamped_t * dy
	proj_coord := Coord{
		lat: proj_lat
		lon: proj_lon
	}
	dist_m := haversine_distance_m(p, proj_coord)

	return PointProjection{
		projected_point: proj_coord
		distance_m: dist_m
		fraction: clamped_t
	}
}

// cross_track_distance_m computes spherical cross-track distance from query point p
// to great circle passing through line segment (a, b).
pub fn cross_track_distance_m(p Coord, a Coord, b Coord) f64 {
	delta13 := haversine_distance_m(a, p) / earth_mean_radius_m
	theta13 := deg_to_rad(initial_bearing_deg(a, p))
	theta12 := deg_to_rad(initial_bearing_deg(a, b))

	dxt := math.asin(math.sin(delta13) * math.sin(theta13 - theta12))
	return math.abs(dxt * earth_mean_radius_m)
}

// douglas_peucker simplifies a polyline within perpendicular distance tolerance in meters.
pub fn douglas_peucker(points []Coord, tolerance_m f64) []Coord {
	if points.len <= 2 {
		return points.clone()
	}

	mut max_dist := 0.0
	mut max_idx := 0
	start := points[0]
	end := points[points.len - 1]

	for i in 1 .. (points.len - 1) {
		proj := project_point_to_segment(points[i], start, end)
		if proj.distance_m > max_dist {
			max_dist = proj.distance_m
			max_idx = i
		}
	}

	if max_dist > tolerance_m {
		// Recursive split
		left := douglas_peucker(points[..max_idx + 1], tolerance_m)
		right := douglas_peucker(points[max_idx..], tolerance_m)

		mut result := left[..left.len - 1].clone()
		result << right
		return result
	}

	return [start, end]
}

// triangle_area_m2 calculates spherical area of triangle formed by three coordinates.
fn triangle_area_m2(a Coord, b Coord, c Coord) f64 {
	ab := haversine_distance_m(a, b)
	bc := haversine_distance_m(b, c)
	ca := haversine_distance_m(c, a)
	s := (ab + bc + ca) / 2.0
	val := s * (s - ab) * (s - bc) * (s - ca)
	if val <= 0.0 {
		return 0.0
	}
	return math.sqrt(val)
}

// visvalingam_whyatt simplifies a polyline by progressively eliminating points
// with the smallest associated effective triangle area until threshold is met.
pub fn visvalingam_whyatt(points []Coord, min_area_m2 f64) []Coord {
	if points.len <= 2 {
		return points.clone()
	}

	mut active := []Coord{cap: points.len}
	for pt in points {
		active << pt
	}

	for active.len > 2 {
		mut min_area := math.max_f64
		mut min_idx := -1

		for i in 1 .. (active.len - 1) {
			area := triangle_area_m2(active[i - 1], active[i], active[i + 1])
			if area < min_area {
				min_area = area
				min_idx = i
			}
		}

		if min_area < min_area_m2 && min_idx != -1 {
			active.delete(min_idx)
		} else {
			break
		}
	}

	return active
}

// point_in_polygon tests if coordinate falls inside polygon using winding number test.
pub fn point_in_polygon(pt Coord, polygon []Coord) bool {
	if polygon.len < 3 {
		return false
	}
	mut wn := 0 // Winding number counter

	for i in 0 .. polygon.len {
		next_i := (i + 1) % polygon.len
		v1 := polygon[i]
		v2 := polygon[next_i]

		if v1.lat <= pt.lat {
			if v2.lat > pt.lat {
				// Upward edge
				if is_left(v1, v2, pt) > 0.0 {
					wn++
				}
			}
		} else {
			if v2.lat <= pt.lat {
				// Downward edge
				if is_left(v1, v2, pt) < 0.0 {
					wn--
				}
			}
		}
	}

	return wn != 0
}

// is_left evaluates 2D cross-product to determine if point c is left of line (a, b).
// >0 for left of line, =0 for on line, <0 for right of line.
@[inline]
fn is_left(a Coord, b Coord, c Coord) f64 {
	return (b.lon - a.lon) * (c.lat - a.lat) - (c.lon - a.lon) * (b.lat - a.lat)
}

// polygon_area_deg2 calculates planar signed area of a polygon in square degrees via Shoelace theorem.
pub fn polygon_area_deg2(polygon []Coord) f64 {
	if polygon.len < 3 {
		return 0.0
	}
	mut area := 0.0
	for i in 0 .. polygon.len {
		j := (i + 1) % polygon.len
		area += polygon[i].lon * polygon[j].lat
		area -= polygon[j].lon * polygon[i].lat
	}
	return area / 2.0
}

// is_clockwise tests whether polygon vertices are ordered clockwise.
pub fn is_clockwise(polygon []Coord) bool {
	return polygon_area_deg2(polygon) < 0.0
}

// sutherland_hodgman_clip clips a polygon against a rectangular 2D bounding box.
pub fn sutherland_hodgman_clip(polygon []Coord, box BBox2D) []Coord {
	if polygon.len < 3 {
		return []Coord{}
	}

	mut output := polygon.clone()

	// Clip against 4 box boundaries: left, right, bottom, top
	edges := [0, 1, 2, 3]
	for edge in edges {
		if output.len == 0 {
			break
		}
		mut input := output.clone()
		output.clear()

		mut s := input[input.len - 1]
		for e in input {
			if is_inside_edge(e, edge, box) {
				if is_inside_edge(s, edge, box) {
					output << e
				} else {
					output << compute_intersection(s, e, edge, box)
					output << e
				}
			} else if is_inside_edge(s, edge, box) {
				output << compute_intersection(s, e, edge, box)
			}
			s = e
		}
	}

	return output
}

fn is_inside_edge(pt Coord, edge int, box BBox2D) bool {
	return match edge {
		0 { pt.lon >= box.min_lon } // Left
		1 { pt.lon <= box.max_lon } // Right
		2 { pt.lat >= box.min_lat } // Bottom
		3 { pt.lat <= box.max_lat } // Top
		else { false }
	}
}

fn compute_intersection(s Coord, e Coord, edge int, box BBox2D) Coord {
	dlon := e.lon - s.lon
	dlat := e.lat - s.lat

	return match edge {
		0 { // Left edge: lon = min_lon
			t := (box.min_lon - s.lon) / if dlon == 0.0 { 1e-12 } else { dlon }
			Coord{
				lat: s.lat + t * dlat
				lon: box.min_lon
			}
		}
		1 { // Right edge: lon = max_lon
			t := (box.max_lon - s.lon) / if dlon == 0.0 { 1e-12 } else { dlon }
			Coord{
				lat: s.lat + t * dlat
				lon: box.max_lon
			}
		}
		2 { // Bottom edge: lat = min_lat
			t := (box.min_lat - s.lat) / if dlat == 0.0 { 1e-12 } else { dlat }
			Coord{
				lat: box.min_lat
				lon: s.lon + t * dlon
			}
		}
		3 { // Top edge: lat = max_lat
			t := (box.max_lat - s.lat) / if dlat == 0.0 { 1e-12 } else { dlat }
			Coord{
				lat: box.max_lat
				lon: s.lon + t * dlon
			}
		}
		else {
			s
		}
	}
}

// convex_hull computes the convex hull polygon of a set of points using the Monotone Chain algorithm.
pub fn convex_hull(points []Coord) []Coord {
	if points.len <= 2 {
		return points.clone()
	}

	mut sorted := points.clone()
	sorted.sort_with_compare(fn (a &Coord, b &Coord) int {
		if a.lon < b.lon {
			return -1
		}
		if a.lon > b.lon {
			return 1
		}
		if a.lat < b.lat {
			return -1
		}
		if a.lat > b.lat {
			return 1
		}
		return 0
	})

	mut lower := []Coord{}
	for pt in sorted {
		for lower.len >= 2 && is_left(lower[lower.len - 2], lower[lower.len - 1], pt) <= 0.0 {
			lower.pop()
		}
		lower << pt
	}

	mut upper := []Coord{}
	for i := sorted.len - 1; i >= 0; i-- {
		pt := sorted[i]
		for upper.len >= 2 && is_left(upper[upper.len - 2], upper[upper.len - 1], pt) <= 0.0 {
			upper.pop()
		}
		upper << pt
	}

	lower.pop()
	upper.pop()

	mut hull := lower.clone()
	hull << upper
	return hull
}
