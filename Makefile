.PHONY: help check-tools build test fmt decoder-setup validate validate-decode rtl-test clean

SIM ?= icarus
TOPLEVEL_LANG ?= verilog
DUT ?= intra
RTL_SAMPLE_BITS ?= 8
RTL_SOURCE_SAMPLE_BITS ?= $(RTL_SAMPLE_BITS)
RTL_CHROMA_FORMAT_IDC ?= 1
RTL_VISIBLE_WIDTH ?= 4
RTL_VISIBLE_HEIGHT ?= 4
RTL_MAX_VISIBLE_WIDTH ?= 64
RTL_MAX_VISIBLE_HEIGHT ?= 64
MAX_WIDTH ?= 64
MAX_HEIGHT ?= 64

help:
	@printf '%s\n' 'FrameForge targets:'
	@printf '%s\n' '  make check-tools - report required local tools'
	@printf '%s\n' '  make build     - build Rust crate'
	@printf '%s\n' '  make test      - run Rust tests'
	@printf '%s\n' '  make fmt       - format Rust code'
	@printf '%s\n' '  make decoder-setup - find or build external VTM decoder'
	@printf '%s\n' '  make validate INPUT=in.yuv [WIDTH=<w> HEIGHT=<h> MAX_WIDTH=64 MAX_HEIGHT=64 FRAMES=1 FORMAT=yuv420p8|yuv422p8|yuv444p8|...]'
	@printf '%s\n' '  make validate-decode BITSTREAM=out.vvc [DECODED=out.yuv]'
	@printf '%s\n' '  make rtl-test  - run cocotb RTL tests'
	@printf '%s\n' '  make rtl-test DUT=encoder - run minimum encoder RTL smoke test'
	@printf '%s\n' '  make rtl-test DUT=vvc-skeleton - run RTL/Rust VVC skeleton smoke test'
	@printf '%s\n' '  make rtl-test DUT=vvc-coding-tree-scheduler - run local coding-tree geometry/path selection test'
	@printf '%s\n' '  make rtl-test DUT=vvc-luma-partition - run local luma partition geometry test'
	@printf '%s\n' '  make rtl-test DUT=vvc-cabac-body - run generated CABAC body test'
	@printf '%s\n' '  make rtl-test DUT=vvc-cabac - run CABAC top test against SW dump'
	@printf '%s\n' '  make rtl-test DUT=vvc-palette-cabac - run local 4:4:4 palette CABAC sub-block test against SW dump'
	@printf '%s\n' '  make rtl-test DUT=vvc-encoder [RTL_VISIBLE_WIDTH=<w> RTL_VISIBLE_HEIGHT=<h> RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_SAMPLE_BITS=8|10|12|16 RTL_SOURCE_SAMPLE_BITS=8|10|12|16 RTL_CHROMA_FORMAT_IDC=1|2|3] - run generated RTL/software VVC stream test'
	@printf '%s\n' '  make reference-vvc BITSTREAM=out.vvc [INPUT=in.yuv WIDTH=<w> HEIGHT=<h> FRAMES=1 BIT_DEPTH=8|10|12|16 CHROMA_FORMAT=420|422|444] - create real VVC using VTM'
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
	@test -n "$(INPUT)" || { echo 'usage: make validate INPUT=path/to/input_64x64_1f_yuv420p8.yuv [WIDTH=<w> HEIGHT=<h> MAX_WIDTH=64 MAX_HEIGHT=64 FRAMES=1 FORMAT=yuv420p8|yuv422p8|yuv444p8|...]'; exit 2; }
	python3 scripts/validate.py "$(INPUT)" $(if $(WIDTH),--width "$(WIDTH)") $(if $(HEIGHT),--height "$(HEIGHT)") --max-width "$(MAX_WIDTH)" --max-height "$(MAX_HEIGHT)" $(if $(FRAMES),--frames "$(FRAMES)") $(if $(FORMAT),--format "$(FORMAT)")

validate-decode:
	@test -n "$(BITSTREAM)" || { echo 'usage: make validate-decode BITSTREAM=path/to/stream.vvc [DECODED=decoded.yuv]'; exit 2; }
	python3 scripts/validate_decode.py "$(BITSTREAM)" $(if $(DECODED),--output "$(DECODED)")

reference-vvc:
	@test -n "$(BITSTREAM)" || { echo 'usage: make reference-vvc BITSTREAM=path/to/out.vvc [INPUT=in.yuv WIDTH=<w> HEIGHT=<h> RECON=out.yuv FRAMES=1 BIT_DEPTH=8|10|12|16 CHROMA_FORMAT=420|422|444]'; exit 2; }
	python3 scripts/reference_encode_vvc.py --output "$(BITSTREAM)" $(if $(INPUT),--input "$(INPUT)") $(if $(WIDTH),--width "$(WIDTH)") $(if $(HEIGHT),--height "$(HEIGHT)") --frames "$(or $(FRAMES),1)" $(if $(BIT_DEPTH),--bit-depth "$(BIT_DEPTH)") $(if $(CHROMA_FORMAT),--chroma-format "$(CHROMA_FORMAT)") $(if $(RECON),--recon "$(RECON)")

rtl-test:
	$(MAKE) -C tb SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) DUT=$(DUT) RTL_SAMPLE_BITS=$(RTL_SAMPLE_BITS) RTL_SOURCE_SAMPLE_BITS=$(RTL_SOURCE_SAMPLE_BITS) RTL_CHROMA_FORMAT_IDC=$(RTL_CHROMA_FORMAT_IDC) RTL_VISIBLE_WIDTH=$(RTL_VISIBLE_WIDTH) RTL_VISIBLE_HEIGHT=$(RTL_VISIBLE_HEIGHT) RTL_MAX_VISIBLE_WIDTH=$(RTL_MAX_VISIBLE_WIDTH) RTL_MAX_VISIBLE_HEIGHT=$(RTL_MAX_VISIBLE_HEIGHT)

clean:
	cargo clean
	$(MAKE) -C tb clean || true
