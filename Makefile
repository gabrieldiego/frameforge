.PHONY: help check-tools build test fmt decoder-setup validate validate-decode rtl-test clean

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
	@printf '%s\n' '  make validate INPUT=in.yuv [WIDTH=4 HEIGHT=4 FRAMES=1 FORMAT=yuv420p8|yuv420p10le|yuv420p12le|yuv420p16le]'
	@printf '%s\n' '  make validate-decode BITSTREAM=out.vvc [DECODED=out.yuv]'
	@printf '%s\n' '  make rtl-test  - run cocotb RTL tests'
	@printf '%s\n' '  make rtl-test DUT=encoder - run minimum encoder RTL smoke test'
	@printf '%s\n' '  make rtl-test DUT=vvc-skeleton - run RTL/Rust VVC skeleton smoke test'
	@printf '%s\n' '  make rtl-test DUT=vvc-toy4x4 [RTL_SAMPLE_BITS=8|10|12|16] - run generated RTL/software VVC toy stream test'
	@printf '%s\n' '  make reference-vvc BITSTREAM=out.vvc [BIT_DEPTH=8|10|12|16] - create real VVC using VTM'
	@printf '%s\n' '  make clean     - remove local build outputs'

check-tools:
	python3 scripts/configure_dev_env.py

build:
	cargo build

test:
	cargo test

fmt:
	cargo fmt

decoder-setup:
	python3 scripts/ensure_reference_decoder.py

validate:
	@test -n "$(INPUT)" || { echo 'usage: make validate INPUT=path/to/input_4x4_1f_yuv420p8.yuv [WIDTH=4 HEIGHT=4 FRAMES=1 FORMAT=yuv420p8|yuv420p10le|yuv420p12le|yuv420p16le]'; exit 2; }
	python3 scripts/validate.py "$(INPUT)" $(if $(WIDTH),--width "$(WIDTH)") $(if $(HEIGHT),--height "$(HEIGHT)") $(if $(FRAMES),--frames "$(FRAMES)") $(if $(FORMAT),--format "$(FORMAT)")

validate-decode:
	@test -n "$(BITSTREAM)" || { echo 'usage: make validate-decode BITSTREAM=path/to/stream.vvc [DECODED=decoded.yuv]'; exit 2; }
	python3 scripts/validate_decode.py "$(BITSTREAM)" $(if $(DECODED),--output "$(DECODED)")

reference-vvc:
	@test -n "$(BITSTREAM)" || { echo 'usage: make reference-vvc BITSTREAM=path/to/out.vvc [RECON=out.yuv] [FRAMES=1]'; exit 2; }
	python3 scripts/reference_encode_vvc.py --output "$(BITSTREAM)" --frames "$(or $(FRAMES),1)" $(if $(BIT_DEPTH),--bit-depth "$(BIT_DEPTH)") $(if $(RECON),--recon "$(RECON)")

rtl-test:
	$(MAKE) -C tb SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) DUT=$(DUT)

clean:
	cargo clean
	$(MAKE) -C tb clean || true
