module formats

import core
import graph

fn test_geojson_route_serialization() {
	geom := [
		core.Coord{
			lat: 37.7749, lon: -122.4194
		},
		core.Coord{
			lat: 37.7833, lon: -122.4167
		},
	]

	raw_json := route_to_geojson(geom, 1200.5, 95000)
	assert raw_json.contains('FeatureCollection')
	assert raw_json.contains('LineString')
	assert raw_json.contains('-122.4194')
	assert raw_json.contains('37.7749')
	assert raw_json.contains('1200.5')
}

fn test_geojson_to_graph_loader() {
	sample_geojson := '{
		"type": "FeatureCollection",
		"features": [
			{
				"type": "Feature",
				"geometry": {
					"type": "LineString",
					"coordinates": [
						[-122.4200, 37.7749],
						[-122.4150, 37.7749],
						[-122.4100, 37.7749]
					]
				},
				"properties": {
					"name": "Market St",
					"speed_kph": "45"
				}
			}
		]
	}'

	mut builder := graph.new_graph_builder()
	count := load_geojson_to_graph(sample_geojson, mut builder) or { panic('failed to load') }

	assert count == 1
	g := builder.build()
	assert g.edge_count() == 1
	assert g.edges[0].name == 'Market St'
	assert g.edges[0].geometry.len == 3
}
