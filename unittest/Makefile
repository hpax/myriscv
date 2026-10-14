# Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
#
# Compile and run self-contained RTL unit tests. Each unit directory contains
# top.sv, bench.sv, and test vectors under tests/.

QUESTA_BIN ?= /opt/altera/bin
QUESTA_ENV = env -i HOME="$(HOME)" PATH="$(QUESTA_BIN):/usr/bin:/bin"
VLIB       = $(QUESTA_ENV) vlib
VMAP       = $(QUESTA_ENV) vmap
VLOG       = $(QUESTA_ENV) vlog
VSIM       = $(QUESTA_ENV) vsim

RTL_DIR     := ../rtl
QUARTUS_DIR := ../quartus
IP_SRCS     := $(addprefix $(QUARTUS_DIR)/, \
	altmult18.v altmult14.v altmult18x15x2.v)
RTL_SRCS    := $(addprefix $(RTL_DIR)/, \
	riscv.sv types.sv mult.sv shifter.sv alu.sv rv32c.sv)
UNITDIRS    := $(sort $(foreach vector,$(wildcard */tests/*.in), \
	$(word 1,$(subst /, ,$(vector)))))

.PHONY: all build run clean $(UNITDIRS) \
	$(addprefix build-,$(UNITDIRS)) $(addprefix run-,$(UNITDIRS))

all: build

build: $(addprefix build-,$(UNITDIRS))

run: $(addprefix run-,$(UNITDIRS))

$(RTL_DIR)/params.vh: $(RTL_DIR)/params.sv $(RTL_DIR)/params.pl
	$(MAKE) -C $(RTL_DIR) params.vh

define unit-rule
$(1): run-$(1)

build-$(1): $(1)/work/.build-stamp

run-$(1): build-$(1)
	@set -e; \
	for input in $(1)/tests/*.in; do \
		output="$$$${input%.in}.out"; \
		echo "Running $$$$input"; \
		$(VSIM) -c -modelsimini $(1)/modelsim.ini -t 1ps \
			-L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver \
			-L altera_lnsim_ver -L cycloneive_ver -L work bench \
			-ginfile=$$$$(realpath "$$$$input") \
			-goutfile=$$$$(realpath "$$$$output") \
			-do "run -all; quit -f"; \
	done

$(1)/work/.build-stamp: $(IP_SRCS) $(RTL_SRCS) $(1)/top.sv $(1)/bench.sv \
	$(RTL_DIR)/params.vh
	-$(QUESTA_ENV) vdel -lib $(1)/work -all
	$(VLIB) $(1)/work
	cd $(1) && $(VMAP) -c
	$(VMAP) -modelsimini $(1)/modelsim.ini work $(1)/work
	$(VLOG) -modelsimini $(1)/modelsim.ini -sv -work work \
		+incdir+$(RTL_DIR) $(IP_SRCS) $(RTL_SRCS) $(1)/top.sv $(1)/bench.sv
	touch $$@
endef

$(foreach unit,$(UNITDIRS),$(eval $(call unit-rule,$(unit))))

clean:
	@for unit in $(UNITDIRS); do \
		$(QUESTA_ENV) vdel -lib "$$unit/work" -all || :; \
		rm -f "$$unit/modelsim.ini" "$$unit/transcript" "$$unit/vsim.wlf" \
			"$$unit"/tests/*.out; \
	done
