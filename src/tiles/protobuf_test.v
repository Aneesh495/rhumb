module tiles

fn test_zigzag_encoding_roundtrip() {
	numbers := [i32(0), i32(-1), i32(1), i32(-2), i32(2), i32(-2147483648), i32(2147483647)]

	for n in numbers {
		z := encode_zigzag32(n)
		recovered := decode_zigzag32(z)
		assert recovered == n
	}

	// Specific test vectors from Protocol Buffers spec:
	// 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3
	assert encode_zigzag32(0) == 0
	assert encode_zigzag32(-1) == 1
	assert encode_zigzag32(1) == 2
	assert encode_zigzag32(-2) == 3
}

fn test_protobuf_varint_and_string() {
	mut pb := new_protobuf_buffer(64)

	// Single byte varint: 1
	pb.write_varint(1)
	assert pb.bytes.len == 1
	assert pb.bytes[0] == 1

	// Two byte varint: 300 (0xAC 0x02)
	pb.clear()
	pb.write_varint(300)
	assert pb.bytes.len == 2
	assert pb.bytes[0] == 0xAC
	assert pb.bytes[1] == 0x02

	// Length-delimited string
	pb.clear()
	pb.write_string(1, 'rhumb')
	// Tag 1 with wire_type 2 is (1 << 3) | 2 = 10 (0x0A)
	assert pb.bytes[0] == 0x0A
	assert pb.bytes[1] == 5 // String length
	assert pb.bytes[2..].bytestr() == 'rhumb'
}

fn (mut pb ProtobufBuffer) clear() {
	pb.bytes.clear()
}
