module routing

// PQItem holds a graph vertex index paired with its scalar distance priority.
pub struct PQItem {
pub mut:
	node     u32
	priority u32
}

// IndexedPriorityQueue implements an indexed binary min-heap supporting O(log N) decrease_key operations.
pub struct IndexedPriorityQueue {
pub mut:
	heap []PQItem
	pos  []int // Maps node ID to its current index within the heap array, or -1 if absent
}

// new_indexed_priority_queue initializes an indexed min-heap sized for max_nodes capacity.
pub fn new_indexed_priority_queue(max_nodes int) IndexedPriorityQueue {
	return IndexedPriorityQueue{
		heap: []PQItem{cap: 1024}
		pos: []int{len: max_nodes, init: -1}
	}
}

// len returns the number of active items in the priority queue.
pub fn (pq &IndexedPriorityQueue) len() int {
	return pq.heap.len
}

// is_empty checks if the queue has no elements.
pub fn (pq &IndexedPriorityQueue) is_empty() bool {
	return pq.heap.len == 0
}

// contains checks whether a vertex is currently in the heap.
pub fn (pq &IndexedPriorityQueue) contains(node u32) bool {
	if int(node) >= pq.pos.len {
		return false
	}
	return pq.pos[node] != -1
}

// push inserts a new node or updates its priority if it is already present.
pub fn (mut pq IndexedPriorityQueue) push(node u32, priority u32) {
	if int(node) >= pq.pos.len {
		// Dynamically grow pos lookup table if graph node index exceeds initial capacity
		new_len := int(node) + 1024
		for pq.pos.len < new_len {
			pq.pos << -1
		}
	}

	if pq.pos[node] != -1 {
		idx := pq.pos[node]
		if priority < pq.heap[idx].priority {
			pq.heap[idx].priority = priority
			pq.sift_up(idx)
		}
		return
	}

	idx := pq.heap.len
	pq.heap << PQItem{
		node: node
		priority: priority
	}
	pq.pos[node] = idx
	pq.sift_up(idx)
}

// pop extracts the item with the minimum priority.
pub fn (mut pq IndexedPriorityQueue) pop() ?(u32, u32) {
	if pq.heap.len == 0 {
		return none
	}

	min_item := pq.heap[0]
	pq.pos[min_item.node] = -1

	last_idx := pq.heap.len - 1
	if last_idx > 0 {
		pq.heap[0] = pq.heap[last_idx]
		pq.pos[pq.heap[0].node] = 0
		pq.heap.trim(last_idx)
		pq.sift_down(0)
	} else {
		pq.heap.trim(0)
	}

	return min_item.node, min_item.priority
}

// decrease_key lowers the priority of an existing node in the heap.
pub fn (mut pq IndexedPriorityQueue) decrease_key(node u32, new_priority u32) {
	if int(node) >= pq.pos.len || pq.pos[node] == -1 {
		pq.push(node, new_priority)
		return
	}
	idx := pq.pos[node]
	if new_priority < pq.heap[idx].priority {
		pq.heap[idx].priority = new_priority
		pq.sift_up(idx)
	}
}

// clear empties the heap and resets position lookups.
pub fn (mut pq IndexedPriorityQueue) clear() {
	for item in pq.heap {
		pq.pos[item.node] = -1
	}
	pq.heap.clear()
}

fn (mut pq IndexedPriorityQueue) sift_up(start_idx int) {
	mut idx := start_idx
	for idx > 0 {
		parent := (idx - 1) / 2
		if pq.heap[idx].priority < pq.heap[parent].priority {
			pq.swap(idx, parent)
			idx = parent
		} else {
			break
		}
	}
}

fn (mut pq IndexedPriorityQueue) sift_down(start_idx int) {
	mut idx := start_idx
	half := pq.heap.len / 2
	for idx < half {
		left := 2 * idx + 1
		right := left + 1
		mut smallest := left

		if right < pq.heap.len && pq.heap[right].priority < pq.heap[left].priority {
			smallest = right
		}

		if pq.heap[smallest].priority < pq.heap[idx].priority {
			pq.swap(idx, smallest)
			idx = smallest
		} else {
			break
		}
	}
}

@[inline]
fn (mut pq IndexedPriorityQueue) swap(i int, j int) {
	node_i := pq.heap[i].node
	node_j := pq.heap[j].node

	pq.pos[node_i] = j
	pq.pos[node_j] = i

	tmp := pq.heap[i]
	pq.heap[i] = pq.heap[j]
	pq.heap[j] = tmp
}
