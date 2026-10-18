#!/usr/bin/make -R -r

PERL = perl

# Used to extract default parameters to a C header file
IVERILOG	= iverilog
IVERILOG_OPTS	= -g2012 -I. -tvvp
VVP		= vvp

.SECONDARY:

.DELETE_ON_ERROR:

all: params.vh params.h

params.vh: params.sv params.pl
	$(PERL) params.pl $< > $@

dumpparams.sv: params.sv params.pl
	$(PERL) params.pl -dump $< > $@

dumpparams.vvp: riscv.sv types.sv functions.sv dumpparams.sv
	$(IVERILOG) $(IVERILOG_OPTS) -sdumpparams -o $@ $^

params.h: dumpparams.vvp
	$(VVP) $(VVP_OPTS) $< -none > $@

clean:
	rm -f params.vh dumpparams.sv dumpparams.vvp params.h
