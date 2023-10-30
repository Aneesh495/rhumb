module routing

import core
import graph

// create_sample_grid_graph generates a deterministic 3x3 planar grid network for routing tests.
pub fn create_sample_grid_graph() graph.Graph {
	mut builder := graph.new_graph_builder()

	for r in 0 .. 3 {
		for c in 0 .. 3 {
			osm_id := i64(r * 3 + c + 1)
			lat := 37.77 + f64(2 - r) * 0.01
			lon := -122.42 + f64(c) * 0.01
			builder.add_node(osm_id, core.Coord{
				lat: lat
				lon: lon
			}, 10.0)
		}
	}

	// Add horizontal bidirectional edges
	for r in 0 .. 3 {
		for c in 0 .. 2 {
			u := u32(r * 3 + c)
			v := u32(r * 3 + c + 1)
			builder.add_edge(u, v, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'E-W St', []core.Coord{})
			builder.add_edge(v, u, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'E-W St', []core.Coord{})
		}
	}

	// Add vertical bidirectional edges
	for r in 0 .. 2 {
		for c in 0 .. 3 {
			u := u32(r * 3 + c)
			v := u32((r + 1) * 3 + c)
			builder.add_edge(u, v, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'N-S Ave', []core.Coord{})
			builder.add_edge(v, u, 1000.0, 50.0, graph.HighwayClass.primary, graph.access_car,
				graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, 'N-S Ave', []core.Coord{})
		}
	}

	return builder.build()
}
