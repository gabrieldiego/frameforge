.PHONY: help check-tools build test fmt decoder-setup validate-decode rtl-test clean

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
DUT ?= intra

help:
	@printf '%s\n' 'FrameForge targets:'
	@printf '%s\n' '  make check-tools - report required local tools'
	@printf '%s\n' '  make build     - build Rust crate'
	@printf '%s\n' '  make test      - run Rust tests'
	@printf '%s\n' '  make fmt       - format Rust code'
	@printf '%s\n' '  make decoder-setup - find or build external VTM decoder'
	@printf '%s\n' '  make validate-decode BITSTREAM=out.vvc [DECODED=out.yuv]'
	@printf '%s\n' '  make rtl-test  - run cocotb RTL tests'
	@printf '%s\n' '  make rtl-test DUT=encoder - run minimum encoder RTL smoke test'
	@printf '%s\n' '  make clean     - remove local build outputs'

check-tools:
	@command -v cargo >/dev/null 2>&1 || { echo 'missing cargo: install a Rust toolchain from https://rustup.rs/'; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo 'missing python3: required for helper scripts and cocotb tests'; exit 1; }
	@command -v cmake >/dev/null 2>&1 || echo 'warning: missing cmake; make decoder-setup cannot build VTM until CMake is installed'
	@command -v cocotb-config >/dev/null 2>&1 || echo 'warning: missing cocotb-config; make rtl-test will not run until cocotb is installed'
	@command -v iverilog >/dev/null 2>&1 || echo 'warning: missing iverilog; make rtl-test with SIM=icarus will not run until Icarus Verilog is installed'

build:
	cargo build

test:
	cargo test

fmt:
	cargo fmt

decoder-setup:
	python3 scripts/ensure_reference_decoder.py

validate-decode:
	@test -n "$(BITSTREAM)" || { echo 'usage: make validate-decode BITSTREAM=path/to/stream.vvc [DECODED=decoded.yuv]'; exit 2; }
	python3 scripts/validate_decode.py "$(BITSTREAM)" $(if $(DECODED),--output "$(DECODED)")

rtl-test:
	$(MAKE) -C tb SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) DUT=$(DUT)

clean:
	cargo clean
	$(MAKE) -C tb clean || true
