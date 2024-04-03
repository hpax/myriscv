#!/usr/bin/make -R -r

PERL = perl

.SECONDARY:

.DELETE_ON_ERROR:

all: params.vh

params.vh: params.sv params.pl
	$(PERL) params.pl $< > $@

clean:
	rm -f params.vh
