.PHONY: help build test fmt rtl-test clean

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

help:
	@printf '%s\n' 'FrameForge targets:'
	@printf '%s\n' '  make build     - build Rust crate'
	@printf '%s\n' '  make test      - run Rust tests'
	@printf '%s\n' '  make fmt       - format Rust code'
	@printf '%s\n' '  make rtl-test  - run cocotb RTL tests'
	@printf '%s\n' '  make clean     - remove local build outputs'

build:
	cargo build

test:
	cargo test

fmt:
	cargo fmt

rtl-test:
	$(MAKE) -C tb SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG)

clean:
	cargo clean
	$(MAKE) -C tb clean || true

