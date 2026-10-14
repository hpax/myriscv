# Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
#
# Build and run the generic SystemVerilog test bench.

QUESTA_BIN ?= /opt/altera/bin
QUESTA_ENV = env -i HOME="$(HOME)" PATH="$(QUESTA_BIN):/usr/bin:/bin"
VLIB       = $(QUESTA_ENV) vlib
VMAP       = $(QUESTA_ENV) vmap
VLOG       = $(QUESTA_ENV) vlog
VSIM       = $(QUESTA_ENV) vsim

RTL_DIR  := ../../rtl
QUARTUS_DIR := ../../quartus
IP_SRCS := $(addprefix $(QUARTUS_DIR)/, \
	altmult18.v altmult14.v altmult18x15x2.v)
RTL_SRCS := $(addprefix $(RTL_DIR)/, \
	riscv.sv types.sv counter.sv tcm.sv shifter.sv rv32c.sv \
	regfile.sv pipeline.sv myriscv.sv mult.sv ldst.sv fetch.sv \
	backend.sv decode.sv alu.sv rng.sv icache.sv)
BENCH_SRCS := test.sv extmem.sv
WORK      := work
STAMP     := $(WORK)/.build-stamp

.PHONY: all run clean FORCE

all: $(STAMP)

$(RTL_DIR)/params.vh: $(RTL_DIR)/params.sv $(RTL_DIR)/params.pl
	$(MAKE) -C $(RTL_DIR) params.vh

$(STAMP): $(IP_SRCS) $(RTL_SRCS) $(BENCH_SRCS) $(RTL_DIR)/params.vh FORCE
	-$(QUESTA_ENV) vdel -lib $(WORK) -all
	$(VLIB) $(WORK)
	$(VMAP) work $(WORK)
	$(VLOG) -sv -work work +incdir+$(RTL_DIR) $(IP_SRCS) $(RTL_SRCS) \
		$(BENCH_SRCS)
	touch $@

run: $(STAMP)
	$(VSIM) -c -t 1ps -L altera_ver -L lpm_ver -L sgate_ver \
		-L altera_mf_ver -L altera_lnsim_ver -L cycloneive_ver \
		-L work test \
		$(if $(TCM_INIT_FILE),+tcm_init=$(TCM_INIT_FILE)) \
		$(if $(MEM_INIT_FILE),+mem_init=$(MEM_INIT_FILE)) \
		-do "run 30 us; quit -f"

clean:
	-$(QUESTA_ENV) vdel -lib $(WORK) -all
	rm -f transcript vsim.wlf

FORCE:
