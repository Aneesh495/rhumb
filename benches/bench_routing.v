module main

import core
import graph
import routing
import time

fn build_benchmark_grid(rows int, cols int) graph.Graph {
	mut builder := graph.new_graph_builder()

	for r in 0 .. rows {
		for c in 0 .. cols {
			osm_id := i64(r * cols + c + 1)
			lat := 37.7000 + f64(r) * 0.002
			lon := -122.5000 + f64(c) * 0.002
			builder.add_node(osm_id, core.Coord{
				lat: lat
				lon: lon
			}, 15.0)
		}
	}

	for r in 0 .. rows {
		for c in 0 .. cols {
			u := u32(r * cols + c)
			// Horizontal edge
			if c + 1 < cols {
				v := u32(r * cols + (c + 1))
				builder.add_edge(u, v, 200.0, 50.0, graph.HighwayClass.primary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Avenue ${r}',
					[]core.Coord{})
				builder.add_edge(v, u, 200.0, 50.0, graph.HighwayClass.primary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Avenue ${r}',
					[]core.Coord{})
			}
			// Vertical edge
			if r + 1 < rows {
				v := u32((r + 1) * cols + c)
				builder.add_edge(u, v, 200.0, 50.0, graph.HighwayClass.secondary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Street ${c}',
					[]core.Coord{})
				builder.add_edge(v, u, 200.0, 50.0, graph.HighwayClass.secondary, graph.access_car,
					graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Street ${c}',
					[]core.Coord{})
			}
		}
	}

	return builder.build()
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
	println('RHUMB ROUTING ENGINE BENCHMARK SUITE')
	println('================================================================================')

	rows := 20
	cols := 20
	total_vertices := rows * cols
	println('Building synthetic planar street grid: ${rows}x${cols} (${total_vertices} vertices)...')
	sw_build := time.new_stopwatch()
	g := build_benchmark_grid(rows, cols)
	build_elapsed := sw_build.elapsed().microseconds()
	println('Graph constructed in ${f64(build_elapsed) / 1000.0:.2f} ms.')
	println('Total Directed Edges: ${g.edge_count()}')
	println('')

	car := graph.car_profile()

	// Contraction Hierarchies Preprocessing
	println('Running Contraction Hierarchies preprocessing...')
	sw_ch := time.new_stopwatch()
	ch_data := routing.ch_preprocess(&g, car)
	ch_elapsed := sw_ch.elapsed().microseconds()
	println('CH preprocessing finished in ${f64(ch_elapsed) / 1000.0:.2f} ms.')
	println('Upward forward edges: ${ch_data.upward_fwd_edges.len}')
	println('')

	iterations := 200
	println('Executing ${iterations} random vertex-pair queries across all algorithms...')
	println('')

	// Generate query pairs
	mut pairs := [][2]u32{cap: iterations}
	for i in 0 .. iterations {
		src := u32((i * 37 + 13) % total_vertices)
		tgt := u32((i * 101 + 47) % total_vertices)
		pairs << [src, tgt]!
	}

	// 1. Dijkstra
	sw_dijkstra := time.new_stopwatch()
	mut dijkstra_paths := 0
	for p in pairs {
		res := routing.dijkstra_shortest_path(&g, p[0], p[1], car) or { continue }
		dijkstra_paths++
		_ = res
	}
	dijkstra_time_us := sw_dijkstra.elapsed().microseconds()
	dijkstra_avg_us := f64(dijkstra_time_us) / f64(iterations)

	// 2. Bidirectional Dijkstra
	sw_bi_dijkstra := time.new_stopwatch()
	mut bi_dijkstra_paths := 0
	for p in pairs {
		res := routing.bidirectional_dijkstra(&g, p[0], p[1], car) or { continue }
		bi_dijkstra_paths++
		_ = res
	}
	bi_dijkstra_time_us := sw_bi_dijkstra.elapsed().microseconds()
	bi_dijkstra_avg_us := f64(bi_dijkstra_time_us) / f64(iterations)

	// 3. A* Search
	sw_astar := time.new_stopwatch()
	mut astar_paths := 0
	for p in pairs {
		res := routing.astar_shortest_path(&g, p[0], p[1], car) or { continue }
		astar_paths++
		_ = res
	}
	astar_time_us := sw_astar.elapsed().microseconds()
	astar_avg_us := f64(astar_time_us) / f64(iterations)

	// 4. Bidirectional A* Search
	sw_bi_astar := time.new_stopwatch()
	mut bi_astar_paths := 0
	for p in pairs {
		res := routing.bidirectional_astar(&g, p[0], p[1], car) or { continue }
		bi_astar_paths++
		_ = res
	}
	bi_astar_time_us := sw_bi_astar.elapsed().microseconds()
	bi_astar_avg_us := f64(bi_astar_time_us) / f64(iterations)

	// 5. Contraction Hierarchies Upward Query
	sw_ch_q := time.new_stopwatch()
	mut ch_paths := 0
	for p in pairs {
		res := routing.ch_query(&ch_data, p[0], p[1], &g) or { continue }
		ch_paths++
		_ = res
	}
	ch_time_us := sw_ch_q.elapsed().microseconds()
	ch_avg_us := f64(ch_time_us) / f64(iterations)

	println('--------------------------------------------------------------------------------')
	println('Algorithm               Total Time (ms)   Avg Latency (us)   Queries / Sec')
	println('--------------------------------------------------------------------------------')
	print_row('Dijkstra (standard)', f64(dijkstra_time_us) / 1000.0, dijkstra_avg_us)
	print_row('Bidirectional Dijkstra', f64(bi_dijkstra_time_us) / 1000.0, bi_dijkstra_avg_us)
	print_row('A* (Haversine)', f64(astar_time_us) / 1000.0, astar_avg_us)
	print_row('Bidirectional A*', f64(bi_astar_time_us) / 1000.0, bi_astar_avg_us)
	print_row('Contraction Hierarchies', f64(ch_time_us) / 1000.0, ch_avg_us)
	println('--------------------------------------------------------------------------------')
	speedup := if ch_avg_us > 0.0 { dijkstra_avg_us / ch_avg_us } else { 1.0 }
	println('Contraction Hierarchies Speedup vs Dijkstra: ${speedup:.1f}x faster')
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
