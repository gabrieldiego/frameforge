.PHONY: help check-tools build test fmt lint decoder-setup validate validate-vtm-synth validate-decode rtl-test synth-env synth-check synth synth-postsim synth-vivado synth-vivado-remote yosys vivado vivado-prepare vivado-config vivado-auth vivado-install vivado-host-deps clean

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
RTL_CTU_SIZE ?= 64
MAX_WIDTH ?= 64
MAX_HEIGHT ?= 64
SYNTH_BOARD ?= synth/boards/arty-z7-10.env
SYNTH_DUT ?= vvc-cabac-stream-writer
SYNTH_FILELIST ?=
SYNTH_TOP ?=
SYNTH_CLOCK_MHZ ?= 50
SYNTH_TOOL ?= $(or $(filter yosys vivado,$(MAKECMDGOALS)),yosys)
VIVADO_REMOTE ?= gabriel@192.168.50.55
VIVADO_REMOTE_ROOT ?= /media/gabriel/Gabriel8TB/Development/frameforge
VIVADO_REMOTE_SSH ?= ssh -F /dev/null
VALIDATE_SYNTH ?= 1
VALIDATE_SYNTH_DUT ?= vvc-cabac-pipeline
VALIDATE_SYNTH_BACKEND ?= yosys
VIVADO_INSTALLER ?=
VIVADO_LICENSE ?=
VIVADO_INSTALL_LOG ?= .tools/vivado-install-run.log

help:
	@printf '%s\n' 'FrameForge targets:'
	@printf '%s\n' '  make check-tools - report required local tools'
	@printf '%s\n' '  make build     - build Rust crate'
	@printf '%s\n' '  make test      - run Rust tests'
	@printf '%s\n' '  make fmt       - format Rust code'
	@printf '%s\n' '  make lint      - run Rust Clippy lints'
	@printf '%s\n' '  make decoder-setup - find or build external VTM decoder'
	@printf '%s\n' '  make validate INPUT=in.yuv [WIDTH=<w> HEIGHT=<h> MAX_WIDTH=64 MAX_HEIGHT=64 FRAMES=1 FORMAT=yuv420p8|yuv422p8|yuv444p8|... VALIDATE_SYNTH_DUT=vvc-cabac-pipeline VALIDATE_SYNTH=1|0]'
	@printf '%s\n' '  make validate-vtm-synth INPUT=in.yuv [WIDTH=<w> HEIGHT=<h> FRAMES=1 FORMAT=yuv420p8 VALIDATE_SYNTH_DUT=vvc-cabac-pipeline VALIDATE_SYNTH_BACKEND=yosys|vivado-remote|none] - compare software stream with VTM, then run synthesis'
	@printf '%s\n' '  make validate-decode BITSTREAM=out.vvc [DECODED=out.yuv]'
	@printf '%s\n' '  make rtl-test  - run cocotb RTL tests'
	@printf '%s\n' '  make rtl-test DUT=encoder - run minimum encoder RTL smoke test'
	@printf '%s\n' '  make rtl-test DUT=vvc-coding-tree-scheduler - run local coding-tree geometry/path selection test'
	@printf '%s\n' '  make rtl-test DUT=vvc-luma-partition - run local luma partition geometry test'
	@printf '%s\n' '  make rtl-test DUT=vvc-cabac - run CABAC top test against SW dump'
	@printf '%s\n' '  make rtl-test DUT=vvc-palette-cabac - run local 4:4:4 palette CABAC sub-block test against SW dump'
	@printf '%s\n' '  make rtl-test DUT=vvc-encoder [RTL_VISIBLE_WIDTH=<w> RTL_VISIBLE_HEIGHT=<h> RTL_MAX_VISIBLE_WIDTH=64 RTL_MAX_VISIBLE_HEIGHT=64 RTL_CTU_SIZE=64 RTL_SAMPLE_BITS=8|10|12|16 RTL_SOURCE_SAMPLE_BITS=8|10|12|16 RTL_CHROMA_FORMAT_IDC=1|2|3] - run generated RTL/software VVC stream test'
	@printf '%s\n' '  make reference-vvc BITSTREAM=out.vvc [INPUT=in.yuv WIDTH=<w> HEIGHT=<h> FRAMES=1 BIT_DEPTH=8|10|12|16 CHROMA_FORMAT=420|422|444] - create real VVC using VTM'
	@printf '%s\n' '  make synth-env - install/detect optional local synthesis tools under .tools/'
	@printf '%s\n' '  make synth-check - detect Yosys/Icarus/Vivado synthesis tools'
	@printf '%s\n' '  make synth [yosys|vivado] [SYNTH_DUT=vvc-cabac-stream-writer SYNTH_BOARD=synth/boards/arty-z7-10.env SYNTH_TOP=<override> SYNTH_FILELIST=<override> SYNTH_CLOCK_MHZ=50] - run selected synthesis estimate plus critical-path report'
	@printf '%s\n' '  make synth-postsim - run Yosys synthesis and a post-synthesis smoke sim when supported'
	@printf '%s\n' '  make synth-vivado - run optional Vivado synthesis/timing if Vivado is installed'
	@printf '%s\n' '  make synth-vivado-remote [VIVADO_REMOTE=user@host VIVADO_REMOTE_ROOT=/path/to/frameforge VIVADO_REMOTE_SSH="ssh -F /dev/null"] - run Vivado synthesis/timing over SSH'
	@printf '%s\n' '  make vivado-prepare [VIVADO_LICENSE=~/Downloads/Xilinx.lic] - create local .tools Vivado directories and ~/.Xilinx cache symlink'
	@printf '%s\n' '  make vivado-config - generate a host-local Vivado install config from the tracked template'
	@printf '%s\n' '  make vivado-auth - run AMD xsetup AuthTokenGen'
	@printf '%s\n' '  make vivado-install - run AMD xsetup batch install using the generated config'
	@printf '%s\n' '  sudo make vivado-host-deps - install host packages required by project-local Vivado'
	@printf '%s\n' '  make clean     - remove local build outputs'

check-tools:
	python3 scripts/configure_dev_env.py

build:
	cargo build

test:
	cargo test

fmt:
	cargo fmt

lint:
	cargo clippy --all-targets -- -D warnings

decoder-setup:
	python3 scripts/ensure_reference_decoder.py

validate:
	@test -n "$(INPUT)" || { echo 'usage: make validate INPUT=path/to/input_64x64_1f_yuv420p8.yuv [WIDTH=<w> HEIGHT=<h> MAX_WIDTH=64 MAX_HEIGHT=64 FRAMES=1 FORMAT=yuv420p8|yuv422p8|yuv444p8|...]'; exit 2; }
	python3 scripts/validate.py "$(INPUT)" $(if $(WIDTH),--width "$(WIDTH)") $(if $(HEIGHT),--height "$(HEIGHT)") --max-width "$(MAX_WIDTH)" --max-height "$(MAX_HEIGHT)" $(if $(FRAMES),--frames "$(FRAMES)") $(if $(FORMAT),--format "$(FORMAT)") --synth-dut "$(VALIDATE_SYNTH_DUT)" $(if $(filter 0,$(VALIDATE_SYNTH)),--skip-synth)

validate-vtm-synth:
	@test -n "$(INPUT)" || { echo 'usage: make validate-vtm-synth INPUT=path/to/input_16x16_1f_yuv420p8.yuv [WIDTH=<w> HEIGHT=<h> FRAMES=1 FORMAT=yuv420p8 VALIDATE_SYNTH_DUT=vvc-cabac-pipeline VALIDATE_SYNTH_BACKEND=yosys|vivado-remote|none]'; exit 2; }
	python3 scripts/validate_vtm_synth.py "$(INPUT)" $(if $(WIDTH),--width "$(WIDTH)") $(if $(HEIGHT),--height "$(HEIGHT)") --max-width "$(MAX_WIDTH)" --max-height "$(MAX_HEIGHT)" $(if $(FRAMES),--frames "$(FRAMES)") $(if $(FORMAT),--format "$(FORMAT)") --synth-dut "$(VALIDATE_SYNTH_DUT)" --synth-backend "$(VALIDATE_SYNTH_BACKEND)" --clock-mhz "$(SYNTH_CLOCK_MHZ)"

validate-decode:
	@test -n "$(BITSTREAM)" || { echo 'usage: make validate-decode BITSTREAM=path/to/stream.vvc [DECODED=decoded.yuv]'; exit 2; }
	python3 scripts/validate_decode.py "$(BITSTREAM)" $(if $(DECODED),--output "$(DECODED)")

reference-vvc:
	@test -n "$(BITSTREAM)" || { echo 'usage: make reference-vvc BITSTREAM=path/to/out.vvc [INPUT=in.yuv WIDTH=<w> HEIGHT=<h> RECON=out.yuv FRAMES=1 BIT_DEPTH=8|10|12|16 CHROMA_FORMAT=420|422|444]'; exit 2; }
	python3 scripts/reference_encode_vvc.py --output "$(BITSTREAM)" $(if $(INPUT),--input "$(INPUT)") $(if $(WIDTH),--width "$(WIDTH)") $(if $(HEIGHT),--height "$(HEIGHT)") --frames "$(or $(FRAMES),1)" $(if $(BIT_DEPTH),--bit-depth "$(BIT_DEPTH)") $(if $(CHROMA_FORMAT),--chroma-format "$(CHROMA_FORMAT)") $(if $(RECON),--recon "$(RECON)")

rtl-test:
	$(MAKE) -C tb SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) DUT=$(DUT) RTL_SAMPLE_BITS=$(RTL_SAMPLE_BITS) RTL_SOURCE_SAMPLE_BITS=$(RTL_SOURCE_SAMPLE_BITS) RTL_CHROMA_FORMAT_IDC=$(RTL_CHROMA_FORMAT_IDC) RTL_VISIBLE_WIDTH=$(RTL_VISIBLE_WIDTH) RTL_VISIBLE_HEIGHT=$(RTL_VISIBLE_HEIGHT) RTL_MAX_VISIBLE_WIDTH=$(RTL_MAX_VISIBLE_WIDTH) RTL_MAX_VISIBLE_HEIGHT=$(RTL_MAX_VISIBLE_HEIGHT) RTL_CTU_SIZE=$(RTL_CTU_SIZE)

synth-env:
	python3 scripts/install_synth_env.py

synth-check:
	python3 scripts/install_synth_env.py --skip-download

synth:
	python3 scripts/run_synth.py --tool "$(SYNTH_TOOL)" --dut "$(SYNTH_DUT)" --board "$(SYNTH_BOARD)" $(if $(SYNTH_FILELIST),--filelist "$(SYNTH_FILELIST)") $(if $(SYNTH_TOP),--top "$(SYNTH_TOP)") --clock-mhz "$(SYNTH_CLOCK_MHZ)"

synth-postsim:
	python3 scripts/run_synth.py --dut "$(SYNTH_DUT)" --board "$(SYNTH_BOARD)" $(if $(SYNTH_FILELIST),--filelist "$(SYNTH_FILELIST)") $(if $(SYNTH_TOP),--top "$(SYNTH_TOP)") --clock-mhz "$(SYNTH_CLOCK_MHZ)" --post-synth-smoke

synth-vivado:
	python3 scripts/run_synth.py --tool vivado --dut "$(SYNTH_DUT)" --board "$(SYNTH_BOARD)" $(if $(SYNTH_FILELIST),--filelist "$(SYNTH_FILELIST)") $(if $(SYNTH_TOP),--top "$(SYNTH_TOP)") --clock-mhz "$(SYNTH_CLOCK_MHZ)"

synth-vivado-remote:
	$(VIVADO_REMOTE_SSH) "$(VIVADO_REMOTE)" 'cd "$(VIVADO_REMOTE_ROOT)" && make synth-vivado SYNTH_DUT="$(SYNTH_DUT)" SYNTH_BOARD="$(SYNTH_BOARD)" SYNTH_CLOCK_MHZ="$(SYNTH_CLOCK_MHZ)" $(if $(SYNTH_FILELIST),SYNTH_FILELIST="$(SYNTH_FILELIST)") $(if $(SYNTH_TOP),SYNTH_TOP="$(SYNTH_TOP)")'

yosys vivado:
	@:

vivado-prepare:
	python3 scripts/setup_vivado.py prepare --link-home-cache $(if $(VIVADO_LICENSE),--license "$(VIVADO_LICENSE)")

vivado-config:
	python3 scripts/setup_vivado.py config

vivado-auth:
	python3 scripts/setup_vivado.py auth

vivado-install:
	python3 scripts/setup_vivado.py install --log "$(VIVADO_INSTALL_LOG)"

vivado-host-deps:
	scripts/install_vivado_host_deps.sh --local

clean:
	cargo clean
	$(MAKE) -C tb clean || true
