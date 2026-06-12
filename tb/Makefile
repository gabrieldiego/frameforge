SIM ?= icarus
TOPLEVEL_LANG ?= verilog
ifneq ("$(wildcard ../.venv/bin/cocotb-config)","")
COCOTB_CONFIG ?= ../.venv/bin/cocotb-config
override PYTHON_BIN := $(abspath ../.venv/bin/python)
export PATH := $(abspath ../.venv/bin):$(PATH)
else
COCOTB_CONFIG ?= cocotb-config
endif

RTL_DIR := ../rtl
CODEC ?= vvc
ifeq ($(CODEC),av2)
DUT ?= av2-encoder
else
DUT ?= vvc-coding-tree-scheduler
endif
RTL_SAMPLE_BITS ?= 8
RTL_SOURCE_SAMPLE_BITS ?= $(RTL_SAMPLE_BITS)
RTL_CHROMA_FORMAT_IDC ?= 1
RTL_VISIBLE_WIDTH ?= 8
RTL_VISIBLE_HEIGHT ?= 8
RTL_MAX_VISIBLE_WIDTH ?= 64
RTL_MAX_VISIBLE_HEIGHT ?= 64
RTL_CTU_SIZE ?= 64
RTL_SUPPORT_PALETTE_444 ?= 1
SIM_BUILD ?= sim_build/$(DUT)-$(RTL_VISIBLE_WIDTH)x$(RTL_VISIBLE_HEIGHT)-$(RTL_SAMPLE_BITS)b-src$(RTL_SOURCE_SAMPLE_BITS)b-cf$(RTL_CHROMA_FORMAT_IDC)
export RTL_SAMPLE_BITS
export RTL_SOURCE_SAMPLE_BITS
export RTL_CHROMA_FORMAT_IDC
export RTL_VISIBLE_WIDTH
export RTL_VISIBLE_HEIGHT
export RTL_MAX_VISIBLE_WIDTH
export RTL_MAX_VISIBLE_HEIGHT
export RTL_CTU_SIZE
export RTL_SUPPORT_PALETTE_444

ifeq ($(CODEC),vvc)
CODEC_RTL_DIR := $(RTL_DIR)/vvc
export PYTHONPATH := $(abspath vvc):$(PYTHONPATH)
else ifeq ($(CODEC),av2)
CODEC_RTL_DIR := $(RTL_DIR)/av2
export PYTHONPATH := $(abspath av2):$(PYTHONPATH)
else
$(error unsupported CODEC '$(CODEC)')
endif

ifeq ($(CODEC),av2)
ifeq ($(DUT),av2-encoder)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/ff_av2_encoder.sv
TOPLEVEL := ff_av2_encoder
COCOTB_TEST_MODULES := test_av2_encoder
else
$(error unsupported AV2 DUT '$(DUT)')
endif
else ifeq ($(DUT),vvc-coding-tree-scheduler)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/ff_vvc_coding_tree_scheduler.sv
TOPLEVEL := ff_vvc_coding_tree_scheduler
COCOTB_TEST_MODULES := test_vvc_coding_tree_scheduler
else ifeq ($(DUT),vvc-palette-symbolizer)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/residual/ff_vvc_chroma_tu_mapper_420.sv $(CODEC_RTL_DIR)/palette/ff_vvc_palette_cu_symbolizer.sv $(CODEC_RTL_DIR)/palette/ff_vvc_palette_symbolizer.sv
TOPLEVEL := ff_vvc_palette_symbolizer
COCOTB_TEST_MODULES := test_vvc_palette_symbolizer
else ifeq ($(DUT),vvc-palette-cu-symbolizer)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/palette/ff_vvc_palette_cu_symbolizer.sv
TOPLEVEL := ff_vvc_palette_cu_symbolizer
COCOTB_TEST_MODULES := test_vvc_palette_cu_symbolizer
else ifeq ($(DUT),residual)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/residual/ff_vvc_residual_transform.sv
TOPLEVEL := ff_vvc_residual_transform
COCOTB_TEST_MODULES := test_vvc_residual_transform
else ifeq ($(DUT),vvc-cabac)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_byte_queue.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bit_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bin_engine.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_context_model.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_stream_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_symbol_binarizer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_syntax_frontend.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_pipeline.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac.sv
TOPLEVEL := ff_vvc_cabac
COCOTB_TEST_MODULES := test_vvc_cabac
else ifeq ($(DUT),vvc-cabac-stream-writer)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_byte_queue.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bit_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bin_engine.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_context_model.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_stream_writer.sv
TOPLEVEL := ff_vvc_cabac_stream_writer
COCOTB_TEST_MODULES := test_vvc_cabac_stream_writer
else ifeq ($(DUT),vvc-cabac-pipeline)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_byte_queue.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bit_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bin_engine.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_context_model.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_stream_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_symbol_binarizer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_syntax_frontend.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_pipeline.sv
TOPLEVEL := ff_vvc_cabac_pipeline
COCOTB_TEST_MODULES := test_vvc_cabac_pipeline
else ifeq ($(DUT),vvc-cabac-symbol-binarizer)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_symbol_binarizer.sv
TOPLEVEL := ff_vvc_cabac_symbol_binarizer
COCOTB_TEST_MODULES := test_vvc_cabac_symbol_binarizer
else ifeq ($(DUT),vvc-cabac-syntax-frontend)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_syntax_frontend.sv
TOPLEVEL := ff_vvc_cabac_syntax_frontend
COCOTB_TEST_MODULES := test_vvc_cabac_syntax_frontend
else ifeq ($(DUT),vvc-cabac-context-model)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_context_model.sv
TOPLEVEL := ff_vvc_cabac_context_model
COCOTB_TEST_MODULES := test_vvc_cabac_context_model
else ifeq ($(DUT),vvc-cabac-bin-engine)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bin_engine.sv
TOPLEVEL := ff_vvc_cabac_bin_engine
COCOTB_TEST_MODULES := test_vvc_cabac_bin_engine
else ifeq ($(DUT),vvc-cabac-bit-writer)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bit_writer.sv
TOPLEVEL := ff_vvc_cabac_bit_writer
COCOTB_TEST_MODULES := test_vvc_cabac_bit_writer
else ifeq ($(DUT),vvc-byte-queue)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_byte_queue.sv
TOPLEVEL := ff_vvc_byte_queue
COCOTB_TEST_MODULES := test_vvc_byte_queue
else ifeq ($(DUT),vvc-emulation-prevention)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/bitstream/ff_vvc_emulation_prevention_stream.sv
TOPLEVEL := ff_vvc_emulation_prevention_stream
COCOTB_TEST_MODULES := test_vvc_emulation_prevention_stream
else ifeq ($(DUT),vvc-ctu-symbolizer)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/cabac/ff_vvc_residual_symbol_emitter_4x4.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_ctu_symbolizer.sv
TOPLEVEL := ff_vvc_ctu_symbolizer
COCOTB_TEST_MODULES := test_vvc_encoder
else ifeq ($(DUT),vvc-encoder)
VERILOG_SOURCES := $(CODEC_RTL_DIR)/residual/ff_vvc_chroma_tu_mapper_420.sv $(CODEC_RTL_DIR)/residual/ff_vvc_chroma_quant_recon_420.sv $(CODEC_RTL_DIR)/residual/ff_vvc_luma_quant_recon_8x8.sv $(CODEC_RTL_DIR)/ff_vvc_coding_tree_scheduler.sv $(CODEC_RTL_DIR)/ff_vvc_cu_activity_mask.sv $(CODEC_RTL_DIR)/ibc/ff_vvc_ibc_hash_matcher.sv $(CODEC_RTL_DIR)/bitstream/ff_vvc_ue_code.sv $(CODEC_RTL_DIR)/ff_vvc_annexb_header.sv $(CODEC_RTL_DIR)/bitstream/ff_vvc_emulation_prevention_stream.sv $(CODEC_RTL_DIR)/bitstream/ff_vvc_annexb_picture_header_stream.sv $(CODEC_RTL_DIR)/bitstream/ff_vvc_annexb_slice_stream.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_residual_symbol_emitter_4x4.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_ctu_symbolizer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_byte_queue.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bit_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_bin_engine.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_context_model.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_stream_writer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_symbol_binarizer.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_syntax_frontend.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac_pipeline.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_cabac.sv $(CODEC_RTL_DIR)/cabac/ff_vvc_rbsp_payload_stream.sv $(CODEC_RTL_DIR)/palette/ff_vvc_palette_cu_symbolizer.sv $(CODEC_RTL_DIR)/palette/ff_vvc_palette_symbolizer.sv $(CODEC_RTL_DIR)/ff_vvc_encoder.sv
TOPLEVEL := ff_vvc_encoder
COCOTB_TEST_MODULES := test_vvc_encoder
else
$(error unsupported DUT '$(DUT)')
endif

COMPILE_ARGS += -g2012
ifeq ($(CODEC),vvc)
COMPILE_ARGS += -I$(CODEC_RTL_DIR)/cabac
endif
ifeq ($(DUT),vvc-encoder)
ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).SAMPLE_BITS=$(RTL_SAMPLE_BITS)
COMPILE_ARGS += -P$(TOPLEVEL).SOURCE_SAMPLE_BITS=$(RTL_SOURCE_SAMPLE_BITS)
COMPILE_ARGS += -P$(TOPLEVEL).MAX_VISIBLE_WIDTH=$(RTL_MAX_VISIBLE_WIDTH)
COMPILE_ARGS += -P$(TOPLEVEL).MAX_VISIBLE_HEIGHT=$(RTL_MAX_VISIBLE_HEIGHT)
COMPILE_ARGS += -P$(TOPLEVEL).CTU_SIZE=$(RTL_CTU_SIZE)
COMPILE_ARGS += -P$(TOPLEVEL).SUPPORT_PALETTE_444=$(RTL_SUPPORT_PALETTE_444)
endif
endif

ifeq ($(filter print-verilog-sources print-toplevel,$(MAKECMDGOALS)),)
.DEFAULT_GOAL := sim
endif

.PHONY: print-verilog-sources print-toplevel

print-verilog-sources:
	@printf '%s\n' $(VERILOG_SOURCES)

print-toplevel:
	@printf '%s\n' $(TOPLEVEL)

ifeq ($(filter print-verilog-sources print-toplevel,$(MAKECMDGOALS)),)
COCOTB_MAKEFILES := $(shell $(COCOTB_CONFIG) --makefiles 2>/dev/null)

ifeq ($(COCOTB_MAKEFILES),)
$(error cocotb-config was not found. Install cocotb to run RTL tests; no proprietary EDA tools are required)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim
endif
