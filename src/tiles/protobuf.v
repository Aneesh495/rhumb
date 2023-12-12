module tiles

// Protobuf wire types according to Google Protocol Buffers specification.
pub const wire_varint = u8(0)
pub const wire_fixed64 = u8(1)
pub const wire_length_delimited = u8(2)
pub const wire_fixed32 = u8(5)

// ProtobufBuffer implements an efficient byte stream encoder for Protocol Buffers wire format.
pub struct ProtobufBuffer {
pub mut:
	bytes []u8
}

// new_protobuf_buffer initializes a buffer with pre-allocated byte capacity.
pub fn new_protobuf_buffer(capacity int) ProtobufBuffer {
	return ProtobufBuffer{
		bytes: []u8{cap: capacity}
	}
}

// encode_zigzag32 transforms a signed 32-bit integer into an unsigned zigzag representation.
@[inline]
pub fn encode_zigzag32(n i32) u32 {
	un := u32(n)
	return (un << 1) ^ u32(n >> 31)
}

// decode_zigzag32 reverses an unsigned zigzag integer back to its signed value.
@[inline]
pub fn decode_zigzag32(z u32) i32 {
	return i32((z >> 1) ^ -(z & 1))
}

// write_tag encodes field number and wire type into the stream.
pub fn (mut pb ProtobufBuffer) write_tag(field_number u32, wire_type u8) {
	tag := (field_number << 3) | u32(wire_type)
	pb.write_varint(u64(tag))
}

// write_varint serializes an unsigned 64-bit integer using variable-length base-128 encoding.
pub fn (mut pb ProtobufBuffer) write_varint(val u64) {
	mut v := val
	for v >= 0x80 {
		pb.bytes << u8((v & 0x7F) | 0x80)
		v >>= 7
	}
	pb.bytes << u8(v & 0x7F)
}

// write_string serializes a length-delimited UTF-8 string field.
pub fn (mut pb ProtobufBuffer) write_string(field_number u32, str string) {
	pb.write_tag(field_number, wire_length_delimited)
	pb.write_varint(u64(str.len))
	for b in str.bytes() {
		pb.bytes << b
	}
}

// write_bytes serializes a raw length-delimited byte slice.
pub fn (mut pb ProtobufBuffer) write_bytes(field_number u32, data []u8) {
	pb.write_tag(field_number, wire_length_delimited)
	pb.write_varint(u64(data.len))
	for b in data {
		pb.bytes << b
	}
}

// write_packed_uint32s serializes a slice of uint32s using protobuf packed encoding.
pub fn (mut pb ProtobufBuffer) write_packed_uint32s(field_number u32, values []u32) {
	if values.len == 0 {
		return
	}
	mut temp := new_protobuf_buffer(values.len * 4)
	for val in values {
		temp.write_varint(u64(val))
	}
	pb.write_bytes(field_number, temp.bytes)
}

// write_embedded embeds another serialized protobuf message as a length-delimited field.
pub fn (mut pb ProtobufBuffer) write_embedded(field_number u32, child ProtobufBuffer) {
	pb.write_bytes(field_number, child.bytes)
}
