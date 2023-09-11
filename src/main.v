module main

import os

fn main() {
	println('rhumb - high-performance geospatial routing and map-matching engine')
	if os.args.len > 1 && os.args[1] == '--version' {
		println('v0.1.0')
		return
	}
}
