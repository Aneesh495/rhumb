module core

fn test_rtree_insert_and_bbox_search() {
	mut tree := new_rtree()
	assert tree.len() == 0

	// Insert 100 points across California
	for i in 0 .. 100 {
		lat := 37.0 + f64(i) * 0.01
		lon := -122.0 - f64(i) * 0.01
		box := new_bbox2d(lat, lon, lat, lon)
		tree.insert(box, u32(i))
	}

	assert tree.len() == 100

	// Query bounding box covering first 10 points
	query_box := new_bbox2d(36.95, -122.15, 37.10, -121.95)
	results := tree.search_bbox(query_box)

	assert results.len >= 10
	for id in results {
		assert id <= 15
	}
}

fn test_rtree_knn_search() {
	mut tree := new_rtree()

	// Insert major cities
	cities := [
		Coord{
			lat: 37.7749, lon: -122.4194
		}, // 0: SF
		Coord{
			lat: 37.8044, lon: -122.2712
		}, // 1: Oakland (~13 km from SF)
		Coord{
			lat: 37.3382, lon: -121.8863
		}, // 2: San Jose (~65 km from SF)
		Coord{
			lat: 38.5816, lon: -121.4944
		}, // 3: Sacramento (~120 km from SF)
		Coord{
			lat: 34.0522, lon: -118.2437
		}, // 4: Los Angeles (~560 km from SF)
	]

	for idx, c in cities {
		box := new_bbox2d(c.lat, c.lon, c.lat, c.lon)
		tree.insert(box, u32(idx))
	}

	sf := cities[0]
	// Nearest 2 cities to SF
	neighbors := tree.nearest_neighbors(sf, 2, 100000.0) // 100km max
	assert neighbors.len == 2
	assert neighbors[0].id == 0 // SF itself (dist 0)
	assert neighbors[0].distance_m == 0.0
	assert neighbors[1].id == 1 // Oakland
	assert neighbors[1].distance_m > 10000.0 && neighbors[1].distance_m < 20000.0
}
