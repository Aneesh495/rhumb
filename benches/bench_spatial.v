module main

import core
import rand
import time

fn pad_right(s string, width int) string {
	if s.len >= width {
		return s
	}
	mut res := s
	for res.len < width {
		res += ' '
	}
	return res
}

fn pad_left(s string, width int) string {
	if s.len >= width {
		return s
	}
	mut res := ''
	for res.len + s.len < width {
		res += ' '
	}
	return res + s
}

fn main() {
	println('================================================================================')
	println('RHUMB HILBERT R*-TREE SPATIAL INDEX BENCHMARK SUITE')
	println('================================================================================')

	num_segments := 10000
	println('Populating Hilbert R*-Tree with ${num_segments} random geospatial segments...')

	mut tree := core.new_rtree()

	// Seed geographic bounds around San Francisco Bay Area (37.7 to 37.9, -122.5 to -122.3)
	mut seg_boxes := []core.BBox2D{cap: num_segments}
	for _ in 0 .. num_segments {
		lat := 37.7000 + rand.f64() * 0.2000
		lon := -122.5000 + rand.f64() * 0.2000
		box := core.BBox2D{
			min_lat: lat
			min_lon: lon
			max_lat: lat + 0.002
			max_lon: lon + 0.002
		}
		seg_boxes << box
	}

	sw_build := time.new_stopwatch()
	for idx, box in seg_boxes {
		tree.insert(box, u32(idx))
	}
	build_elapsed_ms := f64(sw_build.elapsed().microseconds()) / 1000.0
	println('R*-Tree indexing completed in ${build_elapsed_ms:.2f} ms.')
	println('')

	query_count := 1000
	println('Executing ${query_count} spatial bounding box window queries...')

	mut query_boxes := []core.BBox2D{cap: query_count}
	for _ in 0 .. query_count {
		lat := 37.7000 + rand.f64() * 0.1800
		lon := -122.5000 + rand.f64() * 0.1800
		query_boxes << core.BBox2D{
			min_lat: lat
			min_lon: lon
			max_lat: lat + 0.010
			max_lon: lon + 0.010
		}
	}

	// 1. R*-Tree Index Search
	sw_tree := time.new_stopwatch()
	mut tree_hits := 0
	for qb in query_boxes {
		hits := tree.search_bbox(qb)
		tree_hits += hits.len
	}
	tree_us := sw_tree.elapsed().microseconds()
	tree_avg_us := f64(tree_us) / f64(query_count)

	// 2. Linear Scan Brute Force Search
	sw_scan := time.new_stopwatch()
	mut scan_hits := 0
	for qb in query_boxes {
		for idx, box in seg_boxes {
			if qb.intersects(box) {
				scan_hits++
				_ = idx
			}
		}
	}
	scan_us := sw_scan.elapsed().microseconds()
	scan_avg_us := f64(scan_us) / f64(query_count)

	println('--------------------------------------------------------------------------------')
	println('Search Method           Total Time (ms)   Avg Latency (us)   Queries / Sec')
	println('--------------------------------------------------------------------------------')
	print_row('Linear Brute Force', f64(scan_us) / 1000.0, scan_avg_us)
	print_row('Hilbert R*-Tree Index', f64(tree_us) / 1000.0, tree_avg_us)
	println('--------------------------------------------------------------------------------')
	speedup := if tree_avg_us > 0.0 { scan_avg_us / tree_avg_us } else { 1.0 }
	println('R*-Tree Spatial Index Speedup: ${speedup:.1f}x faster than linear scan')
	println('Result Verification: tree_hits=${tree_hits}, scan_hits=${scan_hits} (match: ${tree_hits == scan_hits})')
	println('================================================================================')
}

fn print_row(name string, total_ms f64, avg_us f64) {
	qps := if avg_us > 0.0 { f64(1_000_000) / avg_us } else { 0.0 }
	s_name := pad_right(name, 24)
	s_total := pad_left('${total_ms:.2f} ms', 15)
	s_avg := pad_left('${avg_us:.1f} us', 17)
	s_qps := pad_left('${qps:.0f} qps', 15)
	println('${s_name}${s_total}${s_avg}${s_qps}')
}
