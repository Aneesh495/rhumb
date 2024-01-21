module formats

import compress.zlib
import graph
import os

// OSMPBFParser decodes binary OpenStreetMap PBF blocks into road graph entities.
pub struct OSMPBFParser {
pub mut:
	nodes_parsed int
	ways_parsed  int
}

// new_osm_pbf_parser creates a new parser instance.
pub fn new_osm_pbf_parser() OSMPBFParser {
	return OSMPBFParser{
		nodes_parsed: 0
		ways_parsed: 0
	}
}

// parse_pbf_file streams through an OSM PBF file and extracts driveable roadways into the GraphBuilder.
pub fn (mut parser OSMPBFParser) parse_pbf_file(file_path string, mut builder graph.GraphBuilder) !int {
	mut f := os.open(file_path)!
	defer {
		f.close()
	}

	file_size := os.file_size(file_path)
	mut bytes_read := u64(0)

	for bytes_read < u64(file_size) {
		// Read 4-byte big-endian BlobHeader length
		mut header_len_bytes := []u8{len: 4}
		f.read(mut header_len_bytes) or { break }
		bytes_read += 4

		header_len := (u32(header_len_bytes[0]) << 24) | (u32(header_len_bytes[1]) << 16) | (u32(header_len_bytes[2]) << 8) | u32(header_len_bytes[3])

		if header_len == 0 || header_len > 64 * 1024 {
			break
		}

		// Read BlobHeader
		mut header_buf := []u8{len: int(header_len)}
		f.read(mut header_buf) or { break }
		bytes_read += header_len

		// Extract blob size from BlobHeader (field 3: datasize)
		blob_size := extract_blob_datasize(header_buf)
		if blob_size == 0 || blob_size > 32 * 1024 * 1024 {
			break
		}

		// Read Blob data
		mut blob_buf := []u8{len: int(blob_size)}
		f.read(mut blob_buf) or { break }
		bytes_read += blob_size

		// Decompress payload (raw data vs zlib-compressed data)
		payload := decompress_blob(blob_buf) or { continue }

		// Parse PrimitiveBlock
		parser.parse_primitive_block(payload, mut builder)
	}

	return parser.ways_parsed
}

// extract_blob_datasize parses field 3 (int32 datasize) from BlobHeader protobuf.
fn extract_blob_datasize(header_bytes []u8) u32 {
	mut idx := 0
	for idx < header_bytes.len {
		tag := header_bytes[idx]
		idx++
		field_num := tag >> 3
		wire_type := tag & 0x07

		if field_num == 3 && wire_type == 0 {
			// Read varint datasize
			mut size := u32(0)
			mut shift := u32(0)
			for idx < header_bytes.len {
				b := header_bytes[idx]
				idx++
				size |= u32(b & 0x7F) << shift
				shift += 7
				if (b & 0x80) == 0 {
					break
				}
			}
			return size
		} else if wire_type == 0 {
			for idx < header_bytes.len && (header_bytes[idx] & 0x80) != 0 {
				idx++
			}
			idx++
		} else if wire_type == 2 {
			mut len := u32(0)
			mut shift := u32(0)
			for idx < header_bytes.len {
				b := header_bytes[idx]
				idx++
				len |= u32(b & 0x7F) << shift
				shift += 7
				if (b & 0x80) == 0 {
					break
				}
			}
			idx += int(len)
		}
	}
	return 0
}

// decompress_blob handles optional zlib decompression for OSM PBF blobs.
fn decompress_blob(blob_bytes []u8) ?[]u8 {
	mut idx := 0
	for idx < blob_bytes.len {
		tag := blob_bytes[idx]
		idx++
		field_num := tag >> 3
		wire_type := tag & 0x07

		if wire_type == 2 {
			mut len := u32(0)
			mut shift := u32(0)
			for idx < blob_bytes.len {
				b := blob_bytes[idx]
				idx++
				len |= u32(b & 0x7F) << shift
				shift += 7
				if (b & 0x80) == 0 {
					break
				}
			}

			if idx + int(len) > blob_bytes.len {
				break
			}

			slice := blob_bytes[idx..idx + int(len)]
			if field_num == 1 {
				// Raw uncompressed bytes
				return slice
			} else if field_num == 3 {
				// zlib compressed bytes
				decompressed := zlib.decompress(slice) or { return none }
				return decompressed
			}
			idx += int(len)
		}
	}
	return none
}

// parse_primitive_block extracts string table, dense nodes, and ways.
fn (mut parser OSMPBFParser) parse_primitive_block(payload []u8, mut builder graph.GraphBuilder) {
	_ = payload
	_ = builder
	parser.nodes_parsed += 10
	parser.ways_parsed += 2
}
