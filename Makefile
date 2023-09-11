CC ?= clang
V ?= v
VFLAGS ?= -prod

.PHONY: all build test clean bench fmt lint run

all: build

build:
	mkdir -p bin
	$(V) $(VFLAGS) -o bin/rhumb src/main.v

build-dev:
	mkdir -p bin
	$(V) -g -o bin/rhumb src/main.v

test:
	$(V) test src/core
	$(V) test src/graph
	$(V) test src/routing
	$(V) test src/matcher
	$(V) test src/tiles
	$(V) test src/formats
	$(V) test src/navigation
	$(V) test src/server
	$(V) test tests

bench:
	mkdir -p bin
	$(V) -prod -o bin/bench_routing benches/bench_routing.v
	./bin/bench_routing

fmt:
	$(V) fmt -w src tests benches

clean:
	rm -rf bin/ tmp/ *.o *.dylib *.so *.a
