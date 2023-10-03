module core

import math

fn test_bbox_operations() {
	box1 := new_bbox2d(37.0, -122.5, 38.0, -122.0)
	box2 := new_bbox2d(37.5, -122.2, 38.5, -121.8)
	box3 := new_bbox2d(40.0, -120.0, 41.0, -119.0)

	assert box1.intersects(box2)
	assert !box1.intersects(box3)

	sf := Coord{
		lat: 37.7749
		lon: -122.4194
	}
	assert box1.contains(sf)
	assert !box3.contains(sf)

	center := box1.center()
	assert math.abs(center.lat - 37.5) < 1e-9
	assert math.abs(center.lon - -122.25) < 1e-9

	mut merged := box1
	merged.expand(box3)
	assert merged.contains(box1.center())
	assert merged.contains(box3.center())
}

fn test_point_to_segment_projection() {
	a := Coord{
		lat: 37.0
		lon: -122.0
	}
	b := Coord{
		lat: 37.0
		lon: -121.0
	}
	// Query point exactly north of segment midpoint
	p := Coord{
		lat: 37.1
		lon: -121.5
	}

	proj := project_point_to_segment(p, a, b)
	assert math.abs(proj.fraction - 0.5) < 0.05
	assert math.abs(proj.projected_point.lat - 37.0) < 0.01
	assert math.abs(proj.projected_point.lon - -121.5) < 0.01
	assert proj.distance_m > 10000.0 && proj.distance_m < 12000.0 // ~11.1 km
}

fn test_douglas_peucker_simplification() {
	// A line with an apex deviating perpendicular to the segment
	points := [
		Coord{
			lat: 37.000, lon: -122.000
		},
		Coord{
			lat: 37.025, lon: -122.010
		},
		Coord{
			lat: 37.050, lon: -121.900
		}, // Distinct apex ~11 km east
		Coord{
			lat: 37.075, lon: -122.040
		},
		Coord{
			lat: 37.100, lon: -122.050
		},
	]

	// High tolerance (20 km) collapses to start and end
	simplified_high := douglas_peucker(points, 20000.0)
	assert simplified_high.len == 2

	// Low tolerance (1 km) keeps the apex point
	simplified_low := douglas_peucker(points, 1000.0)
	assert simplified_low.len >= 3
	mut found_apex := false
	for pt in simplified_low {
		if math.abs(pt.lat - 37.050) < 1e-4 {
			found_apex = true
			break
		}
	}
	assert found_apex
}

fn test_visvalingam_whyatt_simplification() {
	points := [
		Coord{
			lat: 37.0, lon: -122.0
		},
		Coord{
			lat: 37.0001, lon: -122.0001
		}, // Tiny triangle ~9,886 m2
		Coord{
			lat: 37.05, lon: -122.03
		}, // Major apex
		Coord{
			lat: 37.1, lon: -122.05
		},
	]

	// Threshold 20,000 m2 should eliminate the small triangle point
	simplified := visvalingam_whyatt(points, 20000.0)
	assert simplified.len == 3
	assert math.abs(simplified[1].lat - 37.05) < 1e-6
}

fn test_point_in_polygon_and_area() {
	// Square polygon around origin
	poly := [
		Coord{
			lat: 10.0, lon: 10.0
		},
		Coord{
			lat: 10.0, lon: 20.0
		},
		Coord{
			lat: 20.0, lon: 20.0
		},
		Coord{
			lat: 20.0, lon: 10.0
		},
	]

	inside := Coord{
		lat: 15.0
		lon: 15.0
	}
	outside := Coord{
		lat: 5.0
		lon: 15.0
	}

	assert point_in_polygon(inside, poly)
	assert !point_in_polygon(outside, poly)

	area := math.abs(polygon_area_deg2(poly))
	assert math.abs(area - 100.0) < 1e-6
}

fn test_sutherland_hodgman_clipping() {
	// Large polygon spanning across bounding box
	poly := [
		Coord{
			lat: 0.0, lon: 0.0
		},
		Coord{
			lat: 0.0, lon: 10.0
		},
		Coord{
			lat: 10.0, lon: 10.0
		},
		Coord{
			lat: 10.0, lon: 0.0
		},
	]
	box := new_bbox2d(2.0, 2.0, 8.0, 8.0)

	clipped := sutherland_hodgman_clip(poly, box)
	assert clipped.len == 4
	for pt in clipped {
		assert box.contains(pt)
	}
}

fn test_convex_hull() {
	points := [
		Coord{
			lat: 0.0, lon: 0.0
		},
		Coord{
			lat: 0.0, lon: 4.0
		},
		Coord{
			lat: 4.0, lon: 4.0
		},
		Coord{
			lat: 4.0, lon: 0.0
		},
		Coord{
			lat: 2.0, lon: 2.0
		}, // Interior point
		Coord{
			lat: 1.0, lon: 3.0
		}, // Interior point
	]

	hull := convex_hull(points)
	assert hull.len == 4
	for pt in hull {
		// Interior points should not be part of the hull
		assert !(pt.lat == 2.0 && pt.lon == 2.0)
		assert !(pt.lat == 1.0 && pt.lon == 3.0)
	}
}
