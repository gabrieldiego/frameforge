SIM ?= icarus
TOPLEVEL_LANG ?= verilog
COCOTB_CONFIG ?= cocotb-config

RTL_DIR := ../rtl
DUT ?= intra

ifeq ($(DUT),encoder)
VERILOG_SOURCES := $(RTL_DIR)/ff_min_encoder_stub.sv
TOPLEVEL := ff_min_encoder_stub
MODULE := test_min_encoder_stub
else
VERILOG_SOURCES := $(RTL_DIR)/ff_intra_pred_stub.sv
TOPLEVEL := ff_intra_pred_stub
MODULE := test_intra_pred_stub
endif

EXTRA_ARGS += -g2012

COCOTB_MAKEFILES := $(shell $(COCOTB_CONFIG) --makefiles 2>/dev/null)

ifeq ($(COCOTB_MAKEFILES),)
$(error cocotb-config was not found. Install cocotb to run RTL tests; no proprietary EDA tools are required)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim
