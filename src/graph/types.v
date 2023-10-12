module graph

import core

// HighwayClass classifies functional road hierarchy according to OpenStreetMap standards.
pub enum HighwayClass {
	motorway
	trunk
	primary
	secondary
	tertiary
	residential
	service
	motorway_link
	trunk_link
	primary_link
	secondary_link
	tertiary_link
	living_street
	cycleway
	footway
	pedestrian
	path
	track
	unclassified
}

// AccessFlag bitmask values controlling vehicle modal permissions.
pub const access_car = u8(1 << 0)
pub const access_bike = u8(1 << 1)
pub const access_foot = u8(1 << 2)
pub const access_hgv = u8(1 << 3)
pub const access_emergency = u8(1 << 4)

// OnewayFlag indicates directional travel constraints on directed edges.
pub enum OnewayFlag {
	bidirectional = 0
	forward_only  = 1
	reverse_only  = 2
}

// SurfaceType captures physical pavement condition for rolling resistance calculations.
pub enum SurfaceType {
	paved
	asphalt
	concrete
	gravel
	dirt
	unpaved
	cobblestone
}

// TurnRestrictionType defines navigational turning interlocks at intersections.
pub enum TurnRestrictionType {
	none
	no_left_turn
	no_right_turn
	no_u_turn
	no_straight_on
	only_left_turn
	only_right_turn
	only_straight_on
}

// infinity_weight represents an impassable routing traversal cost.
pub const infinity_weight = u32(0xFFFFFFFF)

// NodeAttribute stores spatial and topological metadata for a road intersection or vertex.
pub struct NodeAttribute {
pub mut:
	node_id     u32
	coord       core.Coord
	elevation_m f32
	osm_id      i64
}

// EdgeAttribute represents a directed roadway segment with physical properties and geometry.
pub struct EdgeAttribute {
pub mut:
	edge_id    u32
	source     u32
	target     u32
	length_m   f64
	speed_kph  f32
	highway    HighwayClass
	access     u8
	oneway     OnewayFlag
	surface    SurfaceType
	name       string
	geometry   []core.Coord // Sequence of interior vertices including source and target
	bbox       core.BBox2D
}

// TurnRestriction enforces mandatory or forbidden directional transitions across a junction.
pub struct TurnRestriction {
pub:
	from_edge   u32
	via_node    u32
	to_edge     u32
	restriction TurnRestrictionType
}
