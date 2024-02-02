module server

import core
import formats
import graph
import matcher
import navigation
import os
import routing
import strings
import tiles

// ServerConfig configures port, host, and runtime parameters for the Rhumb HTTP engine.
pub struct ServerConfig {
pub:
	port    int    = 8080
	host    string = '127.0.0.1'
	profile graph.VehicleProfile
}

// HTTPServer encapsulates the HTTP daemon, road network graph, and routing engines.
pub struct HTTPServer {
pub mut:
	config    ServerConfig
	graph     &graph.Graph
	ch_router ?routing.ContractedGraph
	matcher   matcher.MapMatcher
}

// new_http_server initializes an HTTP server instance bound to the provided road graph.
pub fn new_http_server(config ServerConfig, g &graph.Graph) HTTPServer {
	return HTTPServer{
		config: config
		graph: g
		ch_router: none
		matcher: matcher.new_map_matcher()
	}
}

// HTTPRequest encapsulates parsed HTTP/1.1 request components.
pub struct HTTPRequest {
pub mut:
	method       string
	path         string
	query_params map[string]string
	headers      map[string]string
	body         string
}

// HTTPResponse encapsulates HTTP response status code, content type, and body.
pub struct HTTPResponse {
pub mut:
	status_code  int
	status_text  string
	content_type string
	body         string
	binary_body  []u8
	is_binary    bool
}

// parse_http_request decodes a raw HTTP/1.1 text stream into structured components.
pub fn parse_http_request(raw string) ?HTTPRequest {
	lines := raw.split('\r\n')
	if lines.len == 0 || lines[0].len == 0 {
		return none
	}

	req_line_parts := lines[0].split(' ')
	if req_line_parts.len < 2 {
		return none
	}

	method := req_line_parts[0]
	full_path := req_line_parts[1]

	// Split path and query parameters
	mut path := full_path
	mut params := map[string]string{}

	if full_path.contains('?') {
		parts := full_path.split('?')
		path = parts[0]
		if parts.len > 1 {
			query_pairs := parts[1].split('&')
			for pair in query_pairs {
				kv := pair.split('=')
				if kv.len == 2 {
					params[kv[0]] = kv[1]
				}
			}
		}
	}

	// Parse headers and body
	mut headers := map[string]string{}
	mut body_start_line := lines.len

	for i in 1 .. lines.len {
		line := lines[i]
		if line.len == 0 {
			body_start_line = i + 1
			break
		}
		colon_idx := line.index(':') or { continue }
		k := line[..colon_idx].trim_space().to_lower()
		v := line[colon_idx + 1..].trim_space()
		headers[k] = v
	}

	mut body := ''
	if body_start_line < lines.len {
		body = lines[body_start_line..].join('\r\n')
	}

	return HTTPRequest{
		method: method
		path: path
		query_params: params
		headers: headers
		body: body
	}
}

// dispatch routes incoming HTTP requests to their respective API handlers.
pub fn (s &HTTPServer) dispatch(req HTTPRequest) HTTPResponse {
	// CORS preflight handling
	if req.method == 'OPTIONS' {
		return HTTPResponse{
			status_code: 204
			status_text: 'No Content'
			content_type: 'text/plain'
			body: ''
			is_binary: false
		}
	}

	if req.path == '/api/v1/health' {
		return s.handle_health()
	}

	if req.path == '/api/v1/route' {
		return s.handle_route(req)
	}

	if req.path == '/api/v1/match' {
		return s.handle_match(req)
	}

	if req.path == '/api/v1/isochrone' {
		return s.handle_isochrone(req)
	}

	if req.path.starts_with('/api/v1/tiles/') {
		return s.handle_tiles(req.path)
	}

	if req.path == '/' || req.path == '/index.html' {
		return s.handle_ui()
	}

	return HTTPResponse{
		status_code: 404
		status_text: 'Not Found'
		content_type: 'application/json'
		body: '{"error":"endpoint not found"}'
		is_binary: false
	}
}

fn (s &HTTPServer) handle_health() HTTPResponse {
	body := '{"status":"ok","engine":"rhumb","version":"0.1.0","nodes":${s.graph.node_count()},"edges":${s.graph.edge_count()}}'
	return HTTPResponse{
		status_code: 200
		status_text: 'OK'
		content_type: 'application/json'
		body: body
		is_binary: false
	}
}

fn (s &HTTPServer) handle_route(req HTTPRequest) HTTPResponse {
	from_str := req.query_params['from'] or {
		return bad_request('missing query parameter "from" (format: lat,lon)')
	}
	to_str := req.query_params['to'] or {
		return bad_request('missing query parameter "to" (format: lat,lon)')
	}

	from_c := parse_lat_lon(from_str) or { return bad_request('invalid "from" coordinates') }
	to_c := parse_lat_lon(to_str) or { return bad_request('invalid "to" coordinates') }

	// Snap coordinates to closest road network vertices
	src_node := s.graph.find_nearest_node(from_c, 2000.0) or {
		return not_found('no road found near start coordinate')
	}
	tgt_node := s.graph.find_nearest_node(to_c, 2000.0) or {
		return not_found('no road found near destination coordinate')
	}

	profile := s.config.profile
	algo := req.query_params['algo'] or { 'dijkstra' }

	opt_res := match algo {
		'astar' { routing.astar_shortest_path(s.graph, src_node, tgt_node, profile) }
		'bi_astar' { routing.bidirectional_astar(s.graph, src_node, tgt_node, profile) }
		'bi_dijkstra' { routing.bidirectional_dijkstra(s.graph, src_node, tgt_node, profile) }
		else { routing.dijkstra_shortest_path(s.graph, src_node, tgt_node, profile) }
	}

	res := opt_res or { return not_found('no route path found between specified points') }

	_ = navigation.generate_guidance(s.graph, res)

	// Serialize into response payload
	geojson_str := formats.route_to_geojson(res.geometry, res.distance_m, res.duration_ms)

	return HTTPResponse{
		status_code: 200
		status_text: 'OK'
		content_type: 'application/json'
		body: geojson_str
		is_binary: false
	}
}

fn (s &HTTPServer) handle_match(req HTTPRequest) HTTPResponse {
	if req.body.len == 0 {
		return bad_request('request body is empty')
	}

	// Parse GPS trajectory from either GPX XML or JSON
	mut trajectory := []matcher.GPSPoint{}
	if req.body.contains('<gpx') {
		trajectory = formats.parse_gpx_track(req.body) or {
			return bad_request('failed to parse GPX content')
		}
	} else {
		// Expect GeoJSON or custom JSON
		return bad_request('unsupported trajectory payload format (please provide GPX 1.1 XML)')
	}

	if trajectory.len == 0 {
		return bad_request('trajectory contains no GPS track points')
	}

	match_res := s.matcher.match_trajectory(s.graph, trajectory, s.config.profile) or {
		return not_found('unable to match trajectory to road network')
	}

	geojson_str := formats.route_to_geojson(match_res.matched_geometry, match_res.total_distance_m,
		u32(match_res.total_distance_m / 10.0 * 1000.0))

	return HTTPResponse{
		status_code: 200
		status_text: 'OK'
		content_type: 'application/json'
		body: geojson_str
		is_binary: false
	}
}

fn (s &HTTPServer) handle_isochrone(req HTTPRequest) HTTPResponse {
	center_str := req.query_params['center'] or {
		return bad_request('missing "center" coordinate (format: lat,lon)')
	}
	center_c := parse_lat_lon(center_str) or { return bad_request('invalid "center" coordinate') }

	center_node := s.graph.find_nearest_node(center_c, 2000.0) or {
		return not_found('no road found near center coordinate')
	}

	mut buckets := [u32(300000), u32(600000), u32(900000)] // 5, 10, 15 min defaults
	if 'time' in req.query_params {
		sec := req.query_params['time'].int()
		if sec > 0 {
			buckets = [u32(sec * 1000)]
		}
	}

	res := routing.compute_isochrones(s.graph, center_node, buckets, s.config.profile)

	mut sb := strings.new_builder(1024)
	sb.write_string('{"type":"FeatureCollection","features":[')

	for i in 0 .. res.buckets.len {
		b := res.buckets[i]
		if i > 0 {
			sb.write_string(',')
		}
		sb.write_string('{"type":"Feature","geometry":{"type":"Polygon","coordinates":[[')
		for j in 0 .. b.polygon.len {
			if j > 0 {
				sb.write_string(',')
			}
			pt := b.polygon[j]
			sb.write_string('[${pt.lon:.6f},${pt.lat:.6f}]')
		}
		sb.write_string(']]},"properties":{"time_ms":${b.duration_ms}}}')
	}
	sb.write_string(']}')

	return HTTPResponse{
		status_code: 200
		status_text: 'OK'
		content_type: 'application/json'
		body: sb.str()
		is_binary: false
	}
}

fn (s &HTTPServer) handle_tiles(path string) HTTPResponse {
	// Parse /api/v1/tiles/:z/:x/:y.mvt
	clean := path.replace('/api/v1/tiles/', '').replace('.mvt', '')
	parts := clean.split('/')
	if parts.len != 3 {
		return bad_request('invalid tile URL path (expected /api/v1/tiles/:z/:x/:y.mvt)')
	}

	z := parts[0].int()
	x := parts[1].int()
	y := parts[2].int()

	tile_bytes := tiles.generate_road_tile(s.graph, z, x, y)

	return HTTPResponse{
		status_code: 200
		status_text: 'OK'
		content_type: 'application/vnd.mapbox-vector-tile'
		body: ''
		binary_body: tile_bytes
		is_binary: true
	}
}

fn (s &HTTPServer) handle_ui() HTTPResponse {
	html_content := os.read_file('web/index.html') or {
		'<html><body><h1>Rhumb Server Active</h1></body></html>'
	}
	return HTTPResponse{
		status_code: 200
		status_text: 'OK'
		content_type: 'text/html; charset=utf-8'
		body: html_content
		is_binary: false
	}
}

fn parse_lat_lon(str string) ?core.Coord {
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

fn bad_request(msg string) HTTPResponse {
	return HTTPResponse{
		status_code: 400
		status_text: 'Bad Request'
		content_type: 'application/json'
		body: '{"error":"${msg}"}'
		is_binary: false
	}
}

fn not_found(msg string) HTTPResponse {
	return HTTPResponse{
		status_code: 404
		status_text: 'Not Found'
		content_type: 'application/json'
		body: '{"error":"${msg}"}'
		is_binary: false
	}
}

// to_wire formats HTTPResponse into wire-ready HTTP/1.1 bytes.
pub fn (resp &HTTPResponse) to_wire() []u8 {
	mut sb := strings.new_builder(256)
	sb.writeln('HTTP/1.1 ${resp.status_code} ${resp.status_text}')
	sb.writeln('Content-Type: ${resp.content_type}')
	sb.writeln('Access-Control-Allow-Origin: *')
	sb.writeln('Access-Control-Allow-Methods: GET, POST, OPTIONS')
	sb.writeln('Access-Control-Allow-Headers: Content-Type')

	content_len := if resp.is_binary { resp.binary_body.len } else { resp.body.len }
	sb.writeln('Content-Length: ${content_len}')
	sb.writeln('Connection: close')
	sb.writeln('')

	mut wire_bytes := sb.str().bytes()
	if resp.is_binary {
		wire_bytes << resp.binary_body
	} else {
		wire_bytes << resp.body.bytes()
	}
	return wire_bytes
}
