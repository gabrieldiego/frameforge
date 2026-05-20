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
SIM_BUILD ?= sim_build/$(DUT)

ifeq ($(DUT),encoder)
VERILOG_SOURCES := $(RTL_DIR)/ff_min_encoder_stub.sv
TOPLEVEL := ff_min_encoder_stub
COCOTB_TEST_MODULES := test_min_encoder_stub
else ifeq ($(DUT),ffbs)
VERILOG_SOURCES := $(RTL_DIR)/ff_ffbs_gray4x4_encoder.sv
TOPLEVEL := ff_ffbs_gray4x4_encoder
COCOTB_TEST_MODULES := test_ffbs_gray4x4_encoder
else ifeq ($(DUT),vvc-skeleton)
VERILOG_SOURCES := $(RTL_DIR)/ff_vvc_skeleton_encoder.sv
TOPLEVEL := ff_vvc_skeleton_encoder
COCOTB_TEST_MODULES := test_vvc_skeleton_encoder
else
VERILOG_SOURCES := $(RTL_DIR)/ff_intra_pred_stub.sv
TOPLEVEL := ff_intra_pred_stub
COCOTB_TEST_MODULES := test_intra_pred_stub
endif

COMPILE_ARGS += -g2012

COCOTB_MAKEFILES := $(shell $(COCOTB_CONFIG) --makefiles 2>/dev/null)

ifeq ($(COCOTB_MAKEFILES),)
$(error cocotb-config was not found. Install cocotb to run RTL tests; no proprietary EDA tools are required)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim
