module server

import core
import graph

fn test_http_request_parsing() {
	raw := 'GET /api/v1/route?from=37.7749,-122.4194&to=37.7833,-122.4167&algo=astar HTTP/1.1\r\nHost: localhost:8080\r\nUser-Agent: test\r\n\r\n'
	req := parse_http_request(raw) or { panic('failed to parse request') }

	assert req.method == 'GET'
	assert req.path == '/api/v1/route'
	assert req.query_params['from'] == '37.7749,-122.4194'
	assert req.query_params['to'] == '37.7833,-122.4167'
	assert req.query_params['algo'] == 'astar'
	assert req.headers['host'] == 'localhost:8080'
}

fn test_http_server_dispatch_and_health() {
	mut builder := graph.new_graph_builder()
	n0 := builder.add_node(1, core.Coord{
		lat: 37.7749, lon: -122.4200
	}, 0.0)
	n1 := builder.add_node(2, core.Coord{
		lat: 37.7749, lon: -122.4100
	}, 0.0)

	builder.add_edge(n0, n1, 800.0, 50.0, graph.HighwayClass.primary, graph.access_car,
		graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Market St', []core.Coord{})

	g := builder.build()
	car := graph.car_profile()

	srv := new_http_server(ServerConfig{
		port: 8080
		host: '127.0.0.1'
		profile: car
	}, &g)

	// Test 1: Health endpoint
	health_req := HTTPRequest{
		method: 'GET'
		path: '/api/v1/health'
		query_params: map[string]string{}
		headers: map[string]string{}
		body: ''
	}
	health_resp := srv.dispatch(health_req)
	assert health_resp.status_code == 200
	assert health_resp.body.contains('"status":"ok"')
	assert health_resp.body.contains('"nodes":2')

	// Test 2: Route endpoint
	mut route_params := map[string]string{}
	route_params['from'] = '37.7749,-122.4200'
	route_params['to'] = '37.7749,-122.4100'

	route_req := HTTPRequest{
		method: 'GET'
		path: '/api/v1/route'
		query_params: route_params
		headers: map[string]string{}
		body: ''
	}
	route_resp := srv.dispatch(route_req)
	assert route_resp.status_code == 200
	assert route_resp.body.contains('FeatureCollection')
	assert route_resp.body.contains('LineString')

	// Test 3: 404 endpoint
	not_found_req := HTTPRequest{
		method: 'GET'
		path: '/unknown'
		query_params: map[string]string{}
		headers: map[string]string{}
		body: ''
	}
	not_found_resp := srv.dispatch(not_found_req)
	assert not_found_resp.status_code == 404
}
