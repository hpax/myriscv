#!/usr/bin/make -R -r

PERL = perl

# Used to extract default parameters to a C header file
IVERILOG	= iverilog
IVERILOG_OPTS	= -g2012 -I./build -I../rtl -tvvp
VVP		= vvp

VPATH = .:./build:../rtl

.SECONDARY:

.DELETE_ON_ERROR:

GEN = params.h riscv.h

all: $(GEN)

# tools contains tools to build generated files
# build contains intermediate files to avoid them being accidentally included

build:
	mkdir -p $@

PTOOL = ../rtl/params.pl

PREQS = ../rtl/params.vh

RTLREQS = $(patsubst %,../rtl/%,riscv.sv types.sv functions.sv)

$(PREQS) &: params.sv
	$(MAKE) -C ../rtl $(PREQS)

build/dumpparams.sv: params.sv $(PTOOL) $(PREQS) | build
	$(PERL) $(PTOOL) -dump -I myriscv.vh -guard MYRISCV_PARAMS_H $< > $@

build/dumpriscv.sv: riscv.sv $(PTOOL) $(PREQS) | build
	$(PERL) $(PTOOL) -dump -I myriscv.vh -guard RISCV_H $< > $@

build/%.vvp: $(RTLREQS) build/%.sv | build
	$(IVERILOG) $(IVERILOG_OPTS) -sdumpparams -o $@ $^

%.h: build/dump%.vvp
	$(VVP) $(VVP_OPTS) $< -none > $@

tidy:
	rm -rf build

clean: tidy
	rm -f $(GEN)
