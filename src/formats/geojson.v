module formats

import core
import graph
import json
import os

// GeoJSONFeatureCollection models a GeoJSON document per RFC 7946.
pub struct GeoJSONFeatureCollection {
pub mut:
	doc_type string           @[json: 'type']
	features []GeoJSONFeature @[json: 'features']
}

// GeoJSONFeature represents a single geographic feature with properties.
pub struct GeoJSONFeature {
pub mut:
	feat_type  string            @[json: 'type']
	geometry   GeoJSONGeometry   @[json: 'geometry']
	properties map[string]string @[json: 'properties']
}

// GeoJSONGeometry represents geometry primitives: Point, LineString, Polygon.
pub struct GeoJSONGeometry {
pub mut:
	geom_type   string   @[json: 'type']
	coordinates [][]f64  @[json: 'coordinates'] // [lon, lat] pairs for LineString
}

// route_to_geojson exports a route polyline with navigation metrics to GeoJSON string.
pub fn route_to_geojson(geometry []core.Coord, distance_m f64, duration_ms u32) string {
	mut coords := [][]f64{cap: geometry.len}
	for pt in geometry {
		coords << [pt.lon, pt.lat]
	}

	mut props := map[string]string{}
	props['distance_m'] = '${distance_m:.1f}'
	props['duration_s'] = '${f64(duration_ms) / 1000.0:.1f}'
	props['duration_ms'] = '${duration_ms}'

	feature := GeoJSONFeature{
		feat_type: 'Feature'
		geometry: GeoJSONGeometry{
			geom_type: 'LineString'
			coordinates: coords
		}
		properties: props
	}

	fc := GeoJSONFeatureCollection{
		doc_type: 'FeatureCollection'
		features: [feature]
	}

	return json.encode(fc)
}

// parse_geojson_linestrings extracts line string features from raw GeoJSON text.
pub fn parse_geojson_linestrings(raw_json string) ?[]GeoJSONFeature {
	fc := json.decode(GeoJSONFeatureCollection, raw_json) or { return none }
	mut result := []GeoJSONFeature{}
	for feat in fc.features {
		if feat.geometry.geom_type == 'LineString' {
			result << feat
		}
	}
	return result
}

// load_geojson_to_graph populates a GraphBuilder from GeoJSON LineString road network data.
pub fn load_geojson_to_graph(raw_json string, mut builder graph.GraphBuilder) ?int {
	features := parse_geojson_linestrings(raw_json) or { return none }
	mut edges_added := 0

	for feat in features {
		coords_raw := feat.geometry.coordinates
		if coords_raw.len < 2 {
			continue
		}

		mut coords := []core.Coord{cap: coords_raw.len}
		for c in coords_raw {
			if c.len >= 2 {
				coords << core.Coord{
					lon: c[0]
					lat: c[1]
				}
			}
		}

		if coords.len < 2 {
			continue
		}

		// Create or lookup node at start and end
		start_id := i64(builder.nodes.len + 1000000)
		end_id := i64(builder.nodes.len + 1000001)

		u := builder.add_node(start_id, coords[0], 0.0)
		v := builder.add_node(end_id, coords[coords.len - 1], 0.0)

		// Calculate total length
		mut total_len := 0.0
		for i in 0 .. (coords.len - 1) {
			total_len += core.haversine_distance_m(coords[i], coords[i + 1])
		}

		road_name := feat.properties['name'] or { 'Unnamed Road' }
		speed := if 'speed_kph' in feat.properties {
			feat.properties['speed_kph'].f32()
		} else {
			50.0
		}

		builder.add_edge(u, v, total_len, speed, graph.HighwayClass.primary, graph.access_car | graph.access_bike,
			graph.OnewayFlag.bidirectional, graph.SurfaceType.asphalt, road_name, coords)
		edges_added++
	}

	return edges_added
}

// load_geojson_network reads and parses a GeoJSON file directly into a Graph.
pub fn load_geojson_network(path string) ?graph.Graph {
	content := os.read_file(path) or { return none }
	mut builder := graph.new_graph_builder()
	load_geojson_to_graph(content, mut builder) or { return none }
	return builder.build()
}
