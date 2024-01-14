module formats

import core
import graph
import os

fn test_binary_graph_roundtrip() {
	mut builder := graph.new_graph_builder()
	n0 := builder.add_node(101, core.Coord{
		lat: 37.7749, lon: -122.4200
	}, 12.5)
	n1 := builder.add_node(102, core.Coord{
		lat: 37.7800, lon: -122.4150
	}, 14.0)
	n2 := builder.add_node(103, core.Coord{
		lat: 37.7850, lon: -122.4100
	}, 16.0)

	builder.add_edge(n0, n1, 550.0, 45.0, graph.HighwayClass.primary, graph.access_car,
		graph.OnewayFlag.forward_only, graph.SurfaceType.asphalt, 'Geary Blvd', []core.Coord{})
	builder.add_edge(n1, n2, 600.0, 40.0, graph.HighwayClass.secondary, graph.access_car | graph.access_bike,
		graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'Van Ness Ave', []core.Coord{})

	g := builder.build()

	tmp_path := '/tmp/test_roundtrip.rhumb'
	save_graph_binary(&g, tmp_path) or { panic('failed to save binary graph') }

	loaded := load_graph_binary(tmp_path) or { panic('failed to load binary graph') }
	os.rm(tmp_path) or {}

	assert loaded.node_count() == 3
	assert loaded.edge_count() == 2

	assert loaded.nodes[0].osm_id == 101
	assert loaded.edges[0].name == 'Geary Blvd'
	assert loaded.edges[1].name == 'Van Ness Ave'
	assert loaded.edges[0].length_m == 550.0
	assert loaded.edges[1].length_m == 600.0
}
