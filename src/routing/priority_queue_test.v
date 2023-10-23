module routing

fn test_indexed_priority_queue_basic() {
	mut pq := new_indexed_priority_queue(10)
	assert pq.is_empty()
	assert pq.len() == 0

	pq.push(3, 300)
	pq.push(1, 100)
	pq.push(2, 200)

	assert pq.len() == 3
	assert pq.contains(1)
	assert pq.contains(2)
	assert pq.contains(3)
	assert !pq.contains(4)

	// Pop order must be priority ascending: 1 (100), 2 (200), 3 (300)
	n1, p1 := pq.pop() or { u32(999), u32(999) }
	assert n1 == 1
	assert p1 == 100

	n2, p2 := pq.pop() or { u32(999), u32(999) }
	assert n2 == 2
	assert p2 == 200

	n3, p3 := pq.pop() or { u32(999), u32(999) }
	assert n3 == 3
	assert p3 == 300

	assert pq.is_empty()
}

fn test_indexed_priority_queue_decrease_key() {
	mut pq := new_indexed_priority_queue(10)
	pq.push(5, 500)
	pq.push(2, 200)
	pq.push(8, 800)

	// Decrease key for node 8 from 800 down to 50
	pq.decrease_key(8, 50)

	// Now node 8 should pop first
	n, p := pq.pop() or { u32(999), u32(999) }
	assert n == 8
	assert p == 50

	n_next, p_next := pq.pop() or { u32(999), u32(999) }
	assert n_next == 2
	assert p_next == 200
}

fn test_indexed_priority_queue_clear() {
	mut pq := new_indexed_priority_queue(10)
	pq.push(1, 10)
	pq.push(2, 20)
	assert pq.len() == 2

	pq.clear()
	assert pq.is_empty()
	assert !pq.contains(1)
	assert !pq.contains(2)

	// Can push again cleanly
	pq.push(1, 5)
	n, p := pq.pop() or { u32(999), u32(999) }
	assert n == 1
	assert p == 5
}
