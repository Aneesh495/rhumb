module tiles

import core
import graph
import math

fn test_tile_pyramid_bounds() {
	// Tile (0, 0, 0) covers the whole world
	b0 := tile_bounds(0, 0, 0)
	assert math.abs(b0.min_lon - -180.0) < 1e-4
	assert math.abs(b0.max_lon - 180.0) < 1e-4

	// San Francisco at zoom 12
	sf := core.Coord{
		lat: 37.7749
		lon: -122.4194
	}
	tx, ty := coord_to_tile(sf, 12)
	assert tx > 0 && tx < 4096
	assert ty > 0 && ty < 4096

	bounds_sf := tile_bounds(12, tx, ty)
	assert bounds_sf.contains(sf)
}

fn test_mvt_linestring_command_encoding() {
	box := core.new_bbox2d(37.0, -122.0, 38.0, -121.0)
	extent := u32(4096)

	points := [
		core.Coord{
			lat: 37.0, lon: -122.0
		},
		core.Coord{
			lat: 37.5, lon: -121.5
		},
		core.Coord{
			lat: 38.0, lon: -121.0
		},
	]

	cmds := encode_linestring_geometry(points, box, extent)
	// Expected: MoveTo(1) command + 2 deltas, LineTo(2) command + 4 deltas = 8 uint32s
	assert cmds.len == 8

	// First command must be MoveTo(1): (1 << 3) | 1 = 9
	assert cmds[0] == 9

	// Second command must be LineTo(2): (2 << 3) | 2 = 18
	assert cmds[3] == 18
}

fn test_mvt_serialization_and_road_tile() {
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

	tx, ty := coord_to_tile(core.Coord{
		lat: 37.7749
		lon: -122.4150
	}, 14)
	tile_bytes := generate_road_tile(&g, 14, tx, ty)

	assert tile_bytes.len > 0
	// MVT root begins with Field 3 (wire_length_delimited): (3 << 3) | 2 = 26 (0x1A)
	assert tile_bytes[0] == 0x1A
}
