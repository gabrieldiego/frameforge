SIM ?= icarus
TOPLEVEL_LANG ?= verilog
ifneq ("$(wildcard ../.venv/bin/cocotb-config)","")
COCOTB_CONFIG ?= ../.venv/bin/cocotb-config
PYTHON_BIN ?= ../.venv/bin/python
export PATH := $(abspath ../.venv/bin):$(PATH)
else
COCOTB_CONFIG ?= cocotb-config
endif

RTL_DIR := ../rtl
DUT ?= intra
RTL_SAMPLE_BITS ?= 8
RTL_SOURCE_SAMPLE_BITS ?= $(RTL_SAMPLE_BITS)
RTL_CHROMA_FORMAT_IDC ?= 1
RTL_VISIBLE_WIDTH ?= 4
RTL_VISIBLE_HEIGHT ?= 4
RTL_MAX_VISIBLE_WIDTH ?= 64
RTL_MAX_VISIBLE_HEIGHT ?= 64
RTL_CTU_SIZE ?= 64
SIM_BUILD ?= sim_build/$(DUT)-$(RTL_VISIBLE_WIDTH)x$(RTL_VISIBLE_HEIGHT)-$(RTL_SAMPLE_BITS)b-src$(RTL_SOURCE_SAMPLE_BITS)b-cf$(RTL_CHROMA_FORMAT_IDC)
export RTL_SAMPLE_BITS
export RTL_SOURCE_SAMPLE_BITS
export RTL_CHROMA_FORMAT_IDC
export RTL_VISIBLE_WIDTH
export RTL_VISIBLE_HEIGHT
export RTL_MAX_VISIBLE_WIDTH
export RTL_MAX_VISIBLE_HEIGHT
export RTL_CTU_SIZE

ifeq ($(DUT),encoder)
VERILOG_SOURCES := $(RTL_DIR)/ff_min_encoder_stub.sv
TOPLEVEL := ff_min_encoder_stub
COCOTB_TEST_MODULES := test_min_encoder_stub
else ifeq ($(DUT),vvc-skeleton)
VERILOG_SOURCES := $(RTL_DIR)/ff_vvc_skeleton_encoder.sv
TOPLEVEL := ff_vvc_skeleton_encoder
COCOTB_TEST_MODULES := test_vvc_skeleton_encoder
else ifeq ($(DUT),vvc-coding-tree-scheduler)
VERILOG_SOURCES := $(RTL_DIR)/ff_vvc_geometry_pkg.sv $(RTL_DIR)/ff_vvc_coding_tree_scheduler.sv
TOPLEVEL := ff_vvc_coding_tree_scheduler
COCOTB_TEST_MODULES := test_vvc_coding_tree_scheduler
else ifeq ($(DUT),vvc-luma-partition)
VERILOG_SOURCES := $(RTL_DIR)/ff_vvc_geometry_pkg.sv $(RTL_DIR)/ff_vvc_luma_partition.sv
TOPLEVEL := ff_vvc_luma_partition
COCOTB_TEST_MODULES := test_vvc_luma_partition
else ifeq ($(DUT),vvc-cabac-body)
VERILOG_SOURCES := $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_stream_writer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_symbolizer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_stream_body.sv $(RTL_DIR)/vvc_cabac/ff_vvc_generated_cabac_body.sv
TOPLEVEL := ff_vvc_generated_cabac_body
COCOTB_TEST_MODULES := test_vvc_generated_cabac_body
else ifeq ($(DUT),vvc-palette-cabac)
VERILOG_SOURCES := $(RTL_DIR)/vvc_palette/ff_vvc_palette_cabac.sv
TOPLEVEL := ff_vvc_palette_cabac
COCOTB_TEST_MODULES := test_vvc_palette_cabac
else ifeq ($(DUT),vvc-palette-symbolizer)
VERILOG_SOURCES := $(RTL_DIR)/vvc_palette/ff_vvc_palette_symbolizer.sv
TOPLEVEL := ff_vvc_palette_symbolizer
COCOTB_TEST_MODULES := test_vvc_palette_symbolizer
else ifeq ($(DUT),residual)
VERILOG_SOURCES := $(RTL_DIR)/vvc_residual/ff_vvc_reconstruction_pkg.sv $(RTL_DIR)/vvc_residual/ff_vvc_residual_transform.sv
TOPLEVEL := ff_vvc_residual_transform
COCOTB_TEST_MODULES := test_vvc_residual_transform
else ifeq ($(DUT),vvc-cabac)
VERILOG_SOURCES := $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_stream_writer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_symbolizer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_stream_body.sv $(RTL_DIR)/vvc_cabac/ff_vvc_generated_cabac_body.sv $(RTL_DIR)/vvc_palette/ff_vvc_palette_cabac.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac.sv
TOPLEVEL := ff_vvc_cabac
COCOTB_TEST_MODULES := test_vvc_palette_cabac
else ifeq ($(DUT),vvc-cabac-stream-writer)
VERILOG_SOURCES := $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_stream_writer.sv
TOPLEVEL := ff_vvc_cabac_stream_writer
COCOTB_TEST_MODULES := test_vvc_cabac_stream_writer
else ifeq ($(DUT),vvc-cabac-8x8-symbolizer)
VERILOG_SOURCES := $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_symbolizer.sv
TOPLEVEL := ff_vvc_cabac_8x8_symbolizer
COCOTB_TEST_MODULES := test_vvc_cabac_8x8_symbolizer
else ifeq ($(DUT),vvc-cabac-8x8-stream-body)
VERILOG_SOURCES := $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_stream_writer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_symbolizer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_stream_body.sv
TOPLEVEL := ff_vvc_cabac_8x8_stream_body
COCOTB_TEST_MODULES := test_vvc_cabac_8x8_stream_body
else ifeq ($(DUT),vvc-encoder)
VERILOG_SOURCES := $(RTL_DIR)/ff_vvc_geometry_pkg.sv $(RTL_DIR)/vvc_residual/ff_vvc_reconstruction_pkg.sv $(RTL_DIR)/vvc_residual/ff_vvc_residual_transform.sv $(RTL_DIR)/ff_vvc_coding_tree_scheduler.sv $(RTL_DIR)/ff_vvc_cu_activity_mask.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_stream_writer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_symbolizer.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac_8x8_stream_body.sv $(RTL_DIR)/vvc_cabac/ff_vvc_generated_cabac_body.sv $(RTL_DIR)/vvc_palette/ff_vvc_palette_cabac.sv $(RTL_DIR)/vvc_cabac/ff_vvc_cabac.sv $(RTL_DIR)/vvc_palette/ff_vvc_palette_symbolizer.sv $(RTL_DIR)/ff_vvc_encoder.sv
TOPLEVEL := ff_vvc_encoder
COCOTB_TEST_MODULES := test_vvc_encoder
else
VERILOG_SOURCES := $(RTL_DIR)/ff_intra_pred_stub.sv
TOPLEVEL := ff_intra_pred_stub
COCOTB_TEST_MODULES := test_intra_pred_stub
endif

COMPILE_ARGS += -g2012
ifeq ($(DUT),vvc-encoder)
ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).SAMPLE_BITS=$(RTL_SAMPLE_BITS)
COMPILE_ARGS += -P$(TOPLEVEL).SOURCE_SAMPLE_BITS=$(RTL_SOURCE_SAMPLE_BITS)
COMPILE_ARGS += -P$(TOPLEVEL).MAX_VISIBLE_WIDTH=$(RTL_MAX_VISIBLE_WIDTH)
COMPILE_ARGS += -P$(TOPLEVEL).MAX_VISIBLE_HEIGHT=$(RTL_MAX_VISIBLE_HEIGHT)
COMPILE_ARGS += -P$(TOPLEVEL).CTU_SIZE=$(RTL_CTU_SIZE)
endif
endif

COCOTB_MAKEFILES := $(shell $(COCOTB_CONFIG) --makefiles 2>/dev/null)

ifeq ($(COCOTB_MAKEFILES),)
$(error cocotb-config was not found. Install cocotb to run RTL tests; no proprietary EDA tools are required)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim
