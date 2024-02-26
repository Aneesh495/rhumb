CC ?= clang
CFLAGS ?= -Wall -Wextra -O3 -I./include
LDFLAGS ?= -L./lib -lrhumb -Wl,-rpath,@loader_path/../lib

all: lib/librhumb.dylib bin/route_example

lib/librhumb.dylib: src/c_bindings.v
	mkdir -p lib
	v -shared -path "@vlib|@vmodules|../src" -o lib/librhumb.dylib src/c_bindings.v

bin/route_example: examples/route_example.c lib/librhumb.dylib
	mkdir -p bin
	$(CC) $(CFLAGS) examples/route_example.c $(LDFLAGS) -o bin/route_example

test: bin/route_example
	./bin/route_example

clean:
	rm -rf lib bin

.PHONY: all test clean
