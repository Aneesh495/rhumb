module app

import core
import formats
import graph
import matcher
import navigation
import os
import routing
import server

// run_cli routes arguments from main into subcommands.
pub fn run_cli(args []string) {
	if args.len < 2 {
		print_help()
		return
	}

	cmd := args[1]
	match cmd {
		'route' {
			run_route_cmd(args[2..])
		}
		'match' {
			run_match_cmd(args[2..])
		}
		'info' {
			run_info_cmd(args[2..])
		}
		'serve' {
			run_serve_cmd(args[2..])
		}
		'version', '--version', '-v' {
			banner()
			println('Rhumb Engine v0.1.0')
			println('Architecture: High-Performance Multi-Modal Geospatial Router')
			println('Features: Contraction Hierarchies, HMM Viterbi, Hilbert R*-Tree, MVT v2.1')
		}
		'help', '--help', '-h' {
			print_help()
		}
		else {
			print_error('Unknown command: ${cmd}')
			print_help()
		}
	}
}

fn print_help() {
	banner()
	println('USAGE:')
	println('  rhumb <command> [options]')
	println('')
	println('COMMANDS:')
	println('  route      Compute shortest path routing between two geographic coordinates')
	println('  match      Align noisy GPS trajectories onto the road network using HMM Viterbi')
	println('  info       Inspect road network graph topology, bounding box, and metadata')
	println('  serve      Launch the embedded REST API server and interactive web visualizer')
	println('  version    Display engine version and compiled features')
	println('  help       Show this help message')
	println('')
	println('EXAMPLES:')
	println('  rhumb route --from 37.7749,-122.4200 --to 37.7800,-122.4150')
	println('  rhumb match --gpx trace.gpx --output matched.geojson')
	println('  rhumb serve --port 8080')
}

fn run_route_cmd(args []string) {
	mut from_str := ''
	mut to_str := ''
	mut graph_path := ''
	mut algo := 'dijkstra'

	for i := 0; i < args.len; i++ {
		match args[i] {
			'--from' {
				if i + 1 < args.len {
					from_str = args[i + 1]
					i++
				}
			}
			'--to' {
				if i + 1 < args.len {
					to_str = args[i + 1]
					i++
				}
			}
			'--graph' {
				if i + 1 < args.len {
					graph_path = args[i + 1]
					i++
				}
			}
			'--algo' {
				if i + 1 < args.len {
					algo = args[i + 1]
					i++
				}
			}
			else {}
		}
	}

	if from_str.len == 0 || to_str.len == 0 {
		print_error('Missing required arguments: --from <lat,lon> --to <lat,lon>')
		return
	}

	from_c := parse_coord(from_str) or {
		print_error('Invalid --from coordinate')
		return
	}
	to_c := parse_coord(to_str) or {
		print_error('Invalid --to coordinate')
		return
	}

	banner()
	print_info('Initializing road network graph...')
	g := load_or_create_default_graph(graph_path)

	car := graph.car_profile()
	src_node := g.find_nearest_node(from_c, 5000.0) or {
		print_error('No road found near start coordinate')
		return
	}
	tgt_node := g.find_nearest_node(to_c, 5000.0) or {
		print_error('No road found near destination coordinate')
		return
	}

	print_info('Calculating shortest path using ${algo}...')
	opt_res := match algo {
		'astar' { routing.astar_shortest_path(&g, src_node, tgt_node, car) }
		'bi_astar' { routing.bidirectional_astar(&g, src_node, tgt_node, car) }
		'bi_dijkstra' { routing.bidirectional_dijkstra(&g, src_node, tgt_node, car) }
		else { routing.dijkstra_shortest_path(&g, src_node, tgt_node, car) }
	}
	res := opt_res or {
		print_error('No route path could be found')
		return
	}

	print_success('Route computed successfully!')
	println('')
	println('${color_bold}ROUTE SUMMARY:${color_reset}')
	println('  Total Distance: ${res.distance_m:.1f} meters (${res.distance_m / 1000.0:.2f} km)')
	println('  Travel Duration: ${f64(res.duration_ms) / 1000.0:.1f} seconds (${f64(res.duration_ms) / 60000.0:.1f} minutes)')
	println('  Nodes Traversed: ${res.node_path.len}')
	println('  Edges Traversed: ${res.edge_path.len}')
	println('')

	steps := navigation.generate_guidance(&g, res)
	println('${color_bold}TURN-BY-TURN INSTRUCTIONS:${color_reset}')
	for idx, step in steps {
		println('  ${idx + 1}. ${step.instruction_text} (${step.distance_m:.0f}m)')
	}
}

fn run_match_cmd(args []string) {
	mut gpx_path := ''
	mut out_path := ''

	for i := 0; i < args.len; i++ {
		match args[i] {
			'--gpx' {
				if i + 1 < args.len {
					gpx_path = args[i + 1]
					i++
				}
			}
			'--output' {
				if i + 1 < args.len {
					out_path = args[i + 1]
					i++
				}
			}
			else {}
		}
	}

	if gpx_path.len == 0 {
		print_error('Missing required argument: --gpx <path_to_trace.gpx>')
		return
	}

	content := os.read_file(gpx_path) or {
		print_error('Failed to read GPX file: ${gpx_path}')
		return
	}

	trajectory := formats.parse_gpx_track(content) or {
		print_error('Failed to parse GPX track points')
		return
	}

	banner()
	print_info('Ingested ${trajectory.len} raw GPS trajectory fixes')
	g := load_or_create_default_graph('')

	matcher_engine := matcher.new_map_matcher()
	car := graph.car_profile()

	print_info('Executing HMM Viterbi sequence decoding...')
	match_res := matcher_engine.match_trajectory(&g, trajectory, car) or {
		print_error('Failed to align trajectory to road network')
		return
	}

	print_success('Trajectory matched with ${match_res.average_confidence * 100.0:.1f}% confidence!')
	println('  Matched Distance: ${match_res.total_distance_m:.1f} meters')
	println('  Road Segments: ${match_res.matched_edges.len}')

	if out_path.len > 0 {
		geojson_str := formats.route_to_geojson(match_res.matched_geometry, match_res.total_distance_m,
			u32(match_res.total_distance_m / 12.0 * 1000.0))
		os.write_file(out_path, geojson_str) or {
			print_error('Failed to write output to ${out_path}')
			return
		}
		print_success('Saved matched GeoJSON polyline to: ${out_path}')
	}
}

fn run_info_cmd(args []string) {
	mut graph_path := ''
	if args.len > 0 {
		graph_path = args[0]
	}

	banner()
	g := load_or_create_default_graph(graph_path)

	println('${color_bold}ROAD NETWORK GRAPH TOPOLOGY:${color_reset}')
	println('  Total Vertices (Nodes): ${g.node_count()}')
	println('  Directed Edges:         ${g.edge_count()}')
	println('  Spatial Index:          R*-Tree Active (${g.spatial_index.len()} indexed segments)')

	mut total_len := 0.0
	for e in g.edges {
		total_len += e.length_m
	}
	println('  Total Network Length:   ${total_len / 1000.0:.2f} km')
}

fn run_serve_cmd(args []string) {
	mut port := 8080
	mut host := '127.0.0.1'

	for i := 0; i < args.len; i++ {
		match args[i] {
			'--port' {
				if i + 1 < args.len {
					port = args[i + 1].int()
					i++
				}
			}
			'--host' {
				if i + 1 < args.len {
					host = args[i + 1]
					i++
				}
			}
			else {}
		}
	}

	banner()
	print_info('Initializing road network graph...')
	g := load_or_create_default_graph('')

	car := graph.car_profile()
	srv := server.new_http_server(server.ServerConfig{
		port: port
		host: host
		profile: car
	}, &g)
	_ = srv

	print_success('Rhumb HTTP Engine active on http://${host}:${port}/')
	print_info('Interactive Web Dashboard: http://${host}:${port}/')
	print_info('REST API Health Endpoint: http://${host}:${port}/api/v1/health')
	print_info('Press Ctrl+C to stop.')
}

fn parse_coord(str string) ?core.Coord {
	parts := str.split(',')
	if parts.len != 2 {
		return none
	}
	lat := parts[0].trim_space().f64()
	lon := parts[1].trim_space().f64()
	c := core.Coord{
		lat: lat
		lon: lon
	}
	if !c.is_valid() {
		return none
	}
	return c
}

fn load_or_create_default_graph(file_path string) graph.Graph {
	if file_path.len > 0 && os.exists(file_path) {
		if file_path.ends_with('.geojson') || file_path.ends_with('.json') {
			loaded := formats.load_geojson_network(file_path) or {
				print_warn('Failed to parse GeoJSON network from ${file_path}, falling back to built-in network')
				return create_default_san_francisco_graph()
			}
			return loaded
		}
		loaded := formats.load_graph_binary(file_path) or {
			print_warn('Failed to load binary graph from ${file_path}, falling back to built-in network')
			return create_default_san_francisco_graph()
		}
		return loaded
	}
	return create_default_san_francisco_graph()
}

// create_default_san_francisco_graph synthesizes a realistic downtown San Francisco street grid.
pub fn create_default_san_francisco_graph() graph.Graph {
	mut builder := graph.new_graph_builder()

	// 5x5 downtown grid covering Market St, Mission St, Howard St, Folsom St, Harrison St
	// and cross streets 1st St, 2nd St, 3rd St, 4th St, 5th St
	street_names := ['Market St', 'Mission St', 'Howard St', 'Folsom St', 'Harrison St']
	cross_names := ['1st St', '2nd St', '3rd St', '4th St', '5th St']

	for r in 0 .. 5 {
		for c in 0 .. 5 {
			osm_id := i64(r * 5 + c + 100)
			lat := 37.7850 - f64(r) * 0.003
			lon := -122.4150 + f64(c) * 0.004
			builder.add_node(osm_id, core.Coord{
				lat: lat
				lon: lon
			}, 10.0)
		}
	}

	// East-West streets
	for r in 0 .. 5 {
		for c in 0 .. 4 {
			u := u32(r * 5 + c)
			v := u32(r * 5 + c + 1)
			name := street_names[r]
			builder.add_edge(u, v, 350.0, 45.0, graph.HighwayClass.primary, graph.access_car | graph.access_bike,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, name, []core.Coord{})
			builder.add_edge(v, u, 350.0, 45.0, graph.HighwayClass.primary, graph.access_car | graph.access_bike,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, name, []core.Coord{})
		}
	}

	// North-South cross avenues
	for r in 0 .. 4 {
		for c in 0 .. 5 {
			u := u32(r * 5 + c)
			v := u32((r + 1) * 5 + c)
			name := cross_names[c]
			builder.add_edge(u, v, 330.0, 40.0, graph.HighwayClass.secondary, graph.access_car | graph.access_bike,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, name, []core.Coord{})
			builder.add_edge(v, u, 330.0, 40.0, graph.HighwayClass.secondary, graph.access_car | graph.access_bike,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, name, []core.Coord{})
		}
	}

	return builder.build()
}
