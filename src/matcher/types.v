module matcher

import core

// GPSPoint represents a raw sensory GPS position fix with optional temporal and kinematic telemetry.
pub struct GPSPoint {
pub:
	coord         core.Coord
	timestamp_sec f64
	speed_mps     f32
	heading_deg   f32
}

// MatchCandidate represents a road network projection candidate for a GPS observation.
pub struct MatchCandidate {
pub:
	edge_id           u32
	projected_coord   core.Coord
	distance_m        f64
	fraction          f64 // Along-track fraction: 0.0 at segment start, 1.0 at segment end
	emission_log_prob f64
}

// MatchedPoint records the alignment between a raw GPS fix and its snapped road network projection.
pub struct MatchedPoint {
pub:
	original_gps  GPSPoint
	matched_coord core.Coord
	edge_id       u32
	distance_m    f64
	confidence    f64 // Normalized confidence score in [0.0, 1.0]
}

// MatchResult packages the complete aligned trajectory, edge sequence, and route geometry.
pub struct MatchResult {
pub mut:
	matched_points     []MatchedPoint
	matched_edges      []u32
	matched_geometry   []core.Coord
	total_distance_m   f64
	average_confidence f64
}
