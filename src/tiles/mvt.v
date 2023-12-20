module tiles

import core
import graph
import math

pub const mvt_default_extent = u32(4096)
pub const mvt_version = u32(2)

// MVTGeomType defines the geometric primitive classes specified in MVT v2.1.
pub enum MVTGeomType {
	unknown    = 0
	point      = 1
	linestring = 2
	polygon    = 3
}

// MVTValue encapsulates polymorphic attribute values supported in vector tile tag dictionaries.
pub struct MVTValue {
pub:
	string_val string
	int_val    i64
	float_val  f64
	bool_val   bool
	val_type   int // 0: string, 1: int, 2: float, 3: bool
}

// MVTFeature models a vector spatial entity with encoded geometry commands and attribute tags.
pub struct MVTFeature {
pub mut:
	id        u64
	tags      []u32 // Pairs of [key_idx, value_idx]
	geom_type MVTGeomType
	geometry  []u32 // Sequence of command integers and zigzag delta coordinates
}

// MVTLayer represents a named vector tile layer containing dictionaries and features.
pub struct MVTLayer {
pub mut:
	name     string
	features []MVTFeature
	keys     []string
	values   []MVTValue
	extent   u32
	version  u32
}

// new_mvt_layer initializes a layer with standard 4096 extent and MVT version 2.
pub fn new_mvt_layer(name string) MVTLayer {
	return MVTLayer{
		name: name
		features: []MVTFeature{}
		keys: []string{}
		values: []MVTValue{}
		extent: mvt_default_extent
		version: mvt_version
	}
}

// add_feature appends a feature with string attributes and encoded geometry.
pub fn (mut layer MVTLayer) add_feature(id u64, geom_type MVTGeomType, geom_cmds []u32, properties map[string]string) {
	mut tag_pairs := []u32{}

	for k, v in properties {
		// Key index
		mut key_idx := -1
		for idx in 0 .. layer.keys.len {
			if layer.keys[idx] == k {
				key_idx = idx
				break
			}
		}
		if key_idx == -1 {
			key_idx = layer.keys.len
			layer.keys << k
		}

		// Value index
		mut val_idx := -1
		for idx in 0 .. layer.values.len {
			if layer.values[idx].val_type == 0 && layer.values[idx].string_val == v {
				val_idx = idx
				break
			}
		}
		if val_idx == -1 {
			val_idx = layer.values.len
			layer.values << MVTValue{
				string_val: v
				int_val: 0
				float_val: 0.0
				bool_val: false
				val_type: 0
			}
		}

		tag_pairs << u32(key_idx)
		tag_pairs << u32(val_idx)
	}

	layer.features << MVTFeature{
		id: id
		tags: tag_pairs
		geom_type: geom_type
		geometry: geom_cmds
	}
}

// encode_linestring_geometry translates an array of geographic coordinates into MVT command integers.
pub fn encode_linestring_geometry(points []core.Coord, box core.BBox2D, extent u32) []u32 {
	if points.len < 2 {
		return []u32{}
	}

	mut cmds := []u32{}
	mut cursor_x := i32(0)
	mut cursor_y := i32(0)

	// Command 1: MoveTo(1)
	cmds << (u32(1) << 3) | u32(1)

	// Project start coordinate
	px0, py0 := project_to_tile_pixels(points[0], box, extent)
	dx0 := px0 - cursor_x
	dy0 := py0 - cursor_y
	cmds << encode_zigzag32(dx0)
	cmds << encode_zigzag32(dy0)
	cursor_x = px0
	cursor_y = py0

	// Command 2: LineTo(points.len - 1)
	line_to_count := u32(points.len - 1)
	cmds << (line_to_count << 3) | u32(2)

	for i in 1 .. points.len {
		px, py := project_to_tile_pixels(points[i], box, extent)
		dx := px - cursor_x
		dy := py - cursor_y
		cmds << encode_zigzag32(dx)
		cmds << encode_zigzag32(dy)
		cursor_x = px
		cursor_y = py
	}

	return cmds
}

// project_to_tile_pixels converts WGS84 geographic coordinate into integer tile pixel coordinates.
@[inline]
pub fn project_to_tile_pixels(pt core.Coord, box core.BBox2D, extent u32) (i32, i32) {
	dlon := box.max_lon - box.min_lon
	dlat := box.max_lat - box.min_lat

	frac_x := if dlon != 0.0 { (pt.lon - box.min_lon) / dlon } else { 0.5 }
	frac_y := if dlat != 0.0 { (box.max_lat - pt.lat) / dlat } else { 0.5 }

	px := i32(math.round(frac_x * f64(extent)))
	py := i32(math.round(frac_y * f64(extent)))

	return px, py
}

// serialize_layer encodes an MVTLayer into its binary protobuf representation.
pub fn (layer &MVTLayer) serialize() ProtobufBuffer {
	mut pb := new_protobuf_buffer(1024)

	// Field 1: string name
	pb.write_string(1, layer.name)

	// Field 2: repeated Feature features
	for feat in layer.features {
		mut feat_pb := new_protobuf_buffer(256)
		feat_pb.write_tag(1, wire_varint)
		feat_pb.write_varint(feat.id)

		if feat.tags.len > 0 {
			feat_pb.write_packed_uint32s(2, feat.tags)
		}

		feat_pb.write_tag(3, wire_varint)
		feat_pb.write_varint(u64(feat.geom_type))

		if feat.geometry.len > 0 {
			feat_pb.write_packed_uint32s(4, feat.geometry)
		}

		pb.write_embedded(2, feat_pb)
	}

	// Field 3: repeated string keys
	for k in layer.keys {
		pb.write_string(3, k)
	}

	// Field 4: repeated Value values
	for val in layer.values {
		mut val_pb := new_protobuf_buffer(64)
		match val.val_type {
			0 { val_pb.write_string(1, val.string_val) }
			1 {
				val_pb.write_tag(4, wire_varint)
				val_pb.write_varint(u64(val.int_val))
			}
			3 {
				val_pb.write_tag(7, wire_varint)
				val_pb.write_varint(if val.bool_val { u64(1) } else { u64(0) })
			}
			else {
				val_pb.write_string(1, val.string_val)
			}
		}
		pb.write_embedded(4, val_pb)
	}

	// Field 5: uint32 extent
	pb.write_tag(5, wire_varint)
	pb.write_varint(u64(layer.extent))

	// Field 15: uint32 version
	pb.write_tag(15, wire_varint)
	pb.write_varint(u64(layer.version))

	return pb
}

// serialize_mvt encodes an array of layers into a standard Mapbox Vector Tile binary stream.
pub fn serialize_mvt(layers []MVTLayer) []u8 {
	mut tile_pb := new_protobuf_buffer(4096)
	for layer in layers {
		layer_pb := layer.serialize()
		tile_pb.write_embedded(3, layer_pb) // Field 3: repeated Layer layers
	}
	return tile_pb.bytes
}

// generate_road_tile creates an MVT vector tile from the road graph for a specific (z, x, y) tile.
pub fn generate_road_tile(g &graph.Graph, z int, x int, y int) []u8 {
	box := tile_bounds(z, x, y)
	candidate_edges := g.spatial_index.search_bbox(box)

	mut road_layer := new_mvt_layer('roads')

	for e_id in candidate_edges {
		edge := g.edges[e_id]
		if edge.geometry.len < 2 {
			continue
		}

		geom_cmds := encode_linestring_geometry(edge.geometry, box, road_layer.extent)
		if geom_cmds.len == 0 {
			continue
		}

		mut props := map[string]string{}
		props['name'] = edge.name
		props['highway'] = '${edge.highway}'
		props['speed_kph'] = '${edge.speed_kph:.0f}'

		road_layer.add_feature(u64(edge.edge_id), MVTGeomType.linestring, geom_cmds, props)
	}

	return serialize_mvt([road_layer])
}
