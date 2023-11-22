module routing

import core
import graph

// IsochroneBucket represents a reachable spatial boundary contour for a specific duration threshold.
pub struct IsochroneBucket {
pub mut:
	duration_ms     u32
	polygon         []core.Coord
	reachable_nodes []u32
}

// IsochroneResult packages all concentric isochrone contours centered around a query location.
pub struct IsochroneResult {
pub mut:
	center  core.Coord
	buckets []IsochroneBucket
}

// compute_isochrones executes a time-bounded wavefront expansion returning concentric reachable polygons.
pub fn compute_isochrones(g &graph.Graph, center_node u32, duration_buckets []u32, profile graph.VehicleProfile) IsochroneResult {
	if int(center_node) >= g.node_count() || duration_buckets.len == 0 {
		return IsochroneResult{
			center: core.Coord{}
			buckets: []IsochroneBucket{}
		}
	}

	mut sorted_buckets := duration_buckets.clone()
	sorted_buckets.sort()
	max_duration := sorted_buckets[sorted_buckets.len - 1]

	num_nodes := g.node_count()
	mut dist := []u32{len: num_nodes, init: graph.infinity_weight}
	mut pq := new_indexed_priority_queue(num_nodes)

	dist[center_node] = 0
	pq.push(center_node, 0)

	// Wavefront expansion up to max_duration
	for !pq.is_empty() {
		u, u_dist := pq.pop() or { break }
		if u_dist > max_duration {
			break
		}

		for e_id in g.out_edges(u) {
			edge := g.edges[e_id]
			cost := profile.compute_traversal_ms(edge)
			if cost == graph.infinity_weight {
				continue
			}

			v := edge.target
			new_dist := u_dist + cost
			if new_dist <= max_duration && new_dist < dist[v] {
				dist[v] = new_dist
				pq.decrease_key(v, new_dist)
			}
		}
	}

	// Partition reached nodes into duration buckets and build bounding contours
	mut result_buckets := []IsochroneBucket{cap: sorted_buckets.len}

	for threshold in sorted_buckets {
		mut bucket_nodes := []u32{}
		mut bucket_coords := []core.Coord{}

		for u in 0 .. num_nodes {
			if dist[u] <= threshold {
				bucket_nodes << u32(u)
				bucket_coords << g.nodes[u].coord
			}
		}

		// Compute convex hull around reachable coordinates to form outer polygon contour
		mut polygon := []core.Coord{}
		if bucket_coords.len >= 3 {
			polygon = core.convex_hull(bucket_coords)
		} else {
			polygon = bucket_coords.clone()
		}

		result_buckets << IsochroneBucket{
			duration_ms: threshold
			polygon: polygon
			reachable_nodes: bucket_nodes
		}
	}

	return IsochroneResult{
		center: g.nodes[center_node].coord
		buckets: result_buckets
	}
}
