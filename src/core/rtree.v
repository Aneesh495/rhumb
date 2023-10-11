module core

import math

pub const rtree_max_entries = 16
pub const rtree_min_entries = 4

// RTreeEntry represents an indexed bounding box paired with an entity identifier.
pub struct RTreeEntry {
pub mut:
	box BBox2D
	id  u32
}

// RTreeNeighbor represents a k-NN search result with computed distance in meters.
pub struct RTreeNeighbor {
pub:
	id         u32
	distance_m f64
}

// RTreeNode represents an internal node or leaf node in the R*-tree hierarchy.
pub struct RTreeNode {
pub mut:
	is_leaf  bool
	box      BBox2D
	entries  []RTreeEntry // Populated when is_leaf is true
	children []&RTreeNode // Populated when is_leaf is false
}

// new_rtree_leaf creates an empty leaf node.
pub fn new_rtree_leaf() &RTreeNode {
	return &RTreeNode{
		is_leaf: true
		box: BBox2D{}
		entries: []RTreeEntry{cap: rtree_max_entries + 1}
		children: []&RTreeNode{}
	}
}

// new_rtree_node creates an empty internal directory node.
pub fn new_rtree_node() &RTreeNode {
	return &RTreeNode{
		is_leaf: false
		box: BBox2D{}
		entries: []RTreeEntry{}
		children: []&RTreeNode{cap: rtree_max_entries + 1}
	}
}

// RTree represents a self-balancing R*-tree spatial index.
pub struct RTree {
pub mut:
	root  &RTreeNode
	count int
}

// new_rtree initializes an empty R*-tree.
pub fn new_rtree() RTree {
	return RTree{
		root: new_rtree_leaf()
		count: 0
	}
}

// len returns the total number of indexed entries.
pub fn (t &RTree) len() int {
	return t.count
}

// recalculate_bbox recomputes the bounding box of a node from its children or entries.
fn (mut n RTreeNode) recalculate_bbox() {
	if n.is_leaf {
		if n.entries.len == 0 {
			n.box = BBox2D{}
			return
		}
		mut b := n.entries[0].box
		for i in 1 .. n.entries.len {
			b.expand(n.entries[i].box)
		}
		n.box = b
	} else {
		if n.children.len == 0 {
			n.box = BBox2D{}
			return
		}
		mut b := n.children[0].box
		for i in 1 .. n.children.len {
			b.expand(n.children[i].box)
		}
		n.box = b
	}
}

// insert adds a new bounding box and entity identifier into the R*-tree.
pub fn (mut t RTree) insert(box BBox2D, id u32) {
	entry := RTreeEntry{
		box: box
		id: id
	}
	mut split_node := t.insert_recursive(mut t.root, entry)
	if !isnil(split_node) {
		// Root split: create new root with two children
		mut new_root := new_rtree_node()
		new_root.children << t.root
		new_root.children << split_node
		new_root.recalculate_bbox()
		t.root = new_root
	}
	t.count++
}

fn (mut t RTree) insert_recursive(mut node RTreeNode, entry RTreeEntry) &RTreeNode {
	if node.is_leaf {
		node.entries << entry
		node.box.expand(entry.box)

		if node.entries.len > rtree_max_entries {
			return node.split_leaf()
		}
		return unsafe { nil }
	}

	// Internal node: choose subtree with least area enlargement
	best_idx := choose_best_child(node, entry.box)
	mut child := node.children[best_idx]
	mut new_child := t.insert_recursive(mut child, entry)
	node.recalculate_bbox()

	if !isnil(new_child) {
		node.children << new_child
		node.recalculate_bbox()
		if node.children.len > rtree_max_entries {
			return node.split_internal()
		}
	}

	return unsafe { nil }
}

fn choose_best_child(node &RTreeNode, box BBox2D) int {
	mut best_idx := 0
	mut min_enlargement := math.max_f64
	mut min_area := math.max_f64

	for i in 0 .. node.children.len {
		child_box := node.children[i].box
		area_before := child_box.area_degrees()

		mut expanded := child_box
		expanded.expand(box)
		area_after := expanded.area_degrees()
		enlargement := area_after - area_before

		if enlargement < min_enlargement {
			min_enlargement = enlargement
			min_area = area_before
			best_idx = i
		} else if math.abs(enlargement - min_enlargement) < 1e-12 {
			if area_before < min_area {
				min_area = area_before
				best_idx = i
			}
		}
	}
	return best_idx
}

// split_leaf splits an overflowing leaf node into two nodes using spatial median split along widest axis.
fn (mut n RTreeNode) split_leaf() &RTreeNode {
	// Determine widest dimension: latitude vs longitude
	dlat := n.box.max_lat - n.box.min_lat
	dlon := n.box.max_lon - n.box.min_lon
	split_lat := dlat >= dlon

	if split_lat {
		n.entries.sort_with_compare(fn (a &RTreeEntry, b &RTreeEntry) int {
			if a.box.min_lat < b.box.min_lat {
				return -1
			}
			if a.box.min_lat > b.box.min_lat {
				return 1
			}
			return 0
		})
	} else {
		n.entries.sort_with_compare(fn (a &RTreeEntry, b &RTreeEntry) int {
			if a.box.min_lon < b.box.min_lon {
				return -1
			}
			if a.box.min_lon > b.box.min_lon {
				return 1
			}
			return 0
		})
	}

	mid := n.entries.len / 2
	mut sibling := new_rtree_leaf()
	for i in mid .. n.entries.len {
		sibling.entries << n.entries[i]
	}
	n.entries.trim(mid)

	n.recalculate_bbox()
	sibling.recalculate_bbox()

	return sibling
}

// split_internal splits an overflowing internal directory node.
fn (mut n RTreeNode) split_internal() &RTreeNode {
	dlat := n.box.max_lat - n.box.min_lat
	dlon := n.box.max_lon - n.box.min_lon
	split_lat := dlat >= dlon

	if split_lat {
		n.children.sort_with_compare(fn (a &&RTreeNode, b &&RTreeNode) int {
			if (*a).box.min_lat < (*b).box.min_lat {
				return -1
			}
			if (*a).box.min_lat > (*b).box.min_lat {
				return 1
			}
			return 0
		})
	} else {
		n.children.sort_with_compare(fn (a &&RTreeNode, b &&RTreeNode) int {
			if (*a).box.min_lon < (*b).box.min_lon {
				return -1
			}
			if (*a).box.min_lon > (*b).box.min_lon {
				return 1
			}
			return 0
		})
	}

	mid := n.children.len / 2
	mut sibling := new_rtree_node()
	for i in mid .. n.children.len {
		sibling.children << n.children[i]
	}
	n.children.trim(mid)

	n.recalculate_bbox()
	sibling.recalculate_bbox()

	return sibling
}

// search_bbox finds all entity identifiers whose bounding boxes intersect the query box.
pub fn (t &RTree) search_bbox(query BBox2D) []u32 {
	mut results := []u32{}
	t.search_recursive(t.root, query, mut results)
	return results
}

fn (t &RTree) search_recursive(node &RTreeNode, query BBox2D, mut results []u32) {
	if !node.box.intersects(query) && t.count > 0 {
		return
	}

	if node.is_leaf {
		for entry in node.entries {
			if entry.box.intersects(query) {
				results << entry.id
			}
		}
	} else {
		for child in node.children {
			if child.box.intersects(query) {
				t.search_recursive(child, query, mut results)
			}
		}
	}
}

// nearest_neighbors performs branch-and-bound k-NN search returning up to k closest entries.
pub fn (t &RTree) nearest_neighbors(pt Coord, k int, max_dist_m f64) []RTreeNeighbor {
	if t.count == 0 || k <= 0 {
		return []RTreeNeighbor{}
	}

	mut candidates := []RTreeNeighbor{}
	t.knn_recursive(t.root, pt, max_dist_m, mut candidates)

	// Sort candidates by distance ascending
	candidates.sort_with_compare(fn (a &RTreeNeighbor, b &RTreeNeighbor) int {
		if a.distance_m < b.distance_m {
			return -1
		}
		if a.distance_m > b.distance_m {
			return 1
		}
		return 0
	})

	if candidates.len > k {
		candidates.trim(k)
	}
	return candidates
}

fn (t &RTree) knn_recursive(node &RTreeNode, pt Coord, max_dist_m f64, mut candidates []RTreeNeighbor) {
	node_dist := dist_to_bbox_m(pt, node.box)
	if node_dist > max_dist_m {
		return
	}

	if node.is_leaf {
		for entry in node.entries {
			d := dist_to_bbox_m(pt, entry.box)
			if d <= max_dist_m {
				candidates << RTreeNeighbor{
					id: entry.id
					distance_m: d
				}
			}
		}
	} else {
		// Sort children by distance to prune subtrees early
		mut sorted_children := node.children.clone()
		sorted_children.sort_with_compare(fn [pt] (a &&RTreeNode, b &&RTreeNode) int {
			da := dist_to_bbox_m(pt, (*a).box)
			db := dist_to_bbox_m(pt, (*b).box)
			if da < db {
				return -1
			}
			if da > db {
				return 1
			}
			return 0
		})

		for child in sorted_children {
			t.knn_recursive(child, pt, max_dist_m, mut candidates)
		}
	}
}

// dist_to_bbox_m calculates minimum spherical distance from point to bounding box.
fn dist_to_bbox_m(pt Coord, box BBox2D) f64 {
	closest_lat := math.clamp(pt.lat, box.min_lat, box.max_lat)
	closest_lon := math.clamp(pt.lon, box.min_lon, box.max_lon)
	closest := Coord{
		lat: closest_lat
		lon: closest_lon
	}
	return haversine_distance_m(pt, closest)
}
