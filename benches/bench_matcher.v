module main

import core
import graph
import matcher
import rand
import time

fn build_benchmark_network() graph.Graph {
	mut builder := graph.new_graph_builder()

	// 10x10 street grid
	for r in 0 .. 10 {
		for c in 0 .. 10 {
			osm_id := i64(r * 10 + c + 1)
			lat := 37.7700 + f64(r) * 0.001
			lon := -122.4200 + f64(c) * 0.001
			builder.add_node(osm_id, core.Coord{
				lat: lat
				lon: lon
			}, 10.0)
		}
	}

	for r in 0 .. 10 {
		for c in 0 .. 10 {
			u := u32(r * 10 + c)
			if c + 1 < 10 {
				v := u32(r * 10 + c + 1)
				builder.add_edge(u, v, 100.0, 45.0, graph.HighwayClass.primary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Street ${r}',
					[]core.Coord{})
				builder.add_edge(v, u, 100.0, 45.0, graph.HighwayClass.primary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Street ${r}',
					[]core.Coord{})
			}
			if r + 1 < 10 {
				v := u32((r + 1) * 10 + c)
				builder.add_edge(u, v, 100.0, 45.0, graph.HighwayClass.secondary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Avenue ${c}',
					[]core.Coord{})
				builder.add_edge(v, u, 100.0, 45.0, graph.HighwayClass.secondary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Avenue ${c}',
					[]core.Coord{})
			}
		}
	}

	return builder.build()
}

fn generate_noisy_trace(points_count int) []matcher.GPSPoint {
	mut trace := []matcher.GPSPoint{cap: points_count}

	mut base_lat := 37.7700
	mut base_lon := -122.4200
	mut timestamp := 1700000000.0

	for i in 0 .. points_count {
		// Simulating vehicle moving along streets with Gaussian noise
		base_lat += 0.0001
		if i % 10 == 0 {
			base_lon += 0.0001
		}

		// Add jitter between -5m and +5m (approx +-0.00005 deg)
		jitter_lat := (rand.f64() - 0.5) * 0.0001
		jitter_lon := (rand.f64() - 0.5) * 0.0001

		trace << matcher.GPSPoint{
			coord: core.Coord{
				lat: base_lat + jitter_lat
				lon: base_lon + jitter_lon
			}
			timestamp_sec: timestamp
			speed_mps: 12.0
			heading_deg: 90.0
		}
		timestamp += 2.0
	}

	return trace
}

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
	println('RHUMB HMM MAP-MATCHING BENCHMARK SUITE')
	println('================================================================================')

	println('Building road network graph with spatial R*-Tree index...')
	g := build_benchmark_network()
	println('Network active: ${g.node_count()} nodes, ${g.edge_count()} edges.')
	println('')

	match_engine := matcher.new_map_matcher()
	car := graph.car_profile()

	trace_sizes := [50, 200, 500, 1000]

	println('Running HMM Viterbi Trellis decoding across varying trajectory lengths...')
	println('--------------------------------------------------------------------------------')
	println('GPS Trace Length   Execution Time (ms)   Per-Point Latency (us)   Points / Sec')
	println('--------------------------------------------------------------------------------')

	for size in trace_sizes {
		trace := generate_noisy_trace(size)

		// Warmup
		_ = match_engine.match_trajectory(&g, trace[..10], car) or { continue }

		sw := time.new_stopwatch()
		res := match_engine.match_trajectory(&g, trace, car) or {
			println('Failed to match trace of size ${size}')
			continue
		}
		elapsed_us := sw.elapsed().microseconds()
		elapsed_ms := f64(elapsed_us) / 1000.0
		per_pt_us := f64(elapsed_us) / f64(size)
		pts_per_sec := if per_pt_us > 0.0 { f64(1_000_000) / per_pt_us } else { 0.0 }

		s_size := pad_right('${size} points', 18)
		s_ms := pad_left('${elapsed_ms:.2f} ms', 21)
		s_us := pad_left('${per_pt_us:.1f} us', 23)
		s_pps := pad_left('${pts_per_sec:.0f} pts/sec', 16)
		println('${s_size}${s_ms}${s_us}${s_pps}')
		_ = res
	}

	println('--------------------------------------------------------------------------------')
	println('Benchmark complete.')
	println('================================================================================')
}
