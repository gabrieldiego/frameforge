.PHONY: help check-tools build test fmt rtl-test clean

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

help:
	@printf '%s\n' 'FrameForge targets:'
	@printf '%s\n' '  make check-tools - report required local tools'
	@printf '%s\n' '  make build     - build Rust crate'
	@printf '%s\n' '  make test      - run Rust tests'
	@printf '%s\n' '  make fmt       - format Rust code'
	@printf '%s\n' '  make rtl-test  - run cocotb RTL tests'
	@printf '%s\n' '  make clean     - remove local build outputs'

check-tools:
	@command -v cargo >/dev/null 2>&1 || { echo 'missing cargo: install a Rust toolchain from https://rustup.rs/'; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo 'missing python3: required for helper scripts and cocotb tests'; exit 1; }
	@command -v cocotb-config >/dev/null 2>&1 || echo 'warning: missing cocotb-config; make rtl-test will not run until cocotb is installed'
	@command -v iverilog >/dev/null 2>&1 || echo 'warning: missing iverilog; make rtl-test with SIM=icarus will not run until Icarus Verilog is installed'

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
