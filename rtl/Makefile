#!/usr/bin/make -R -r

PERL = perl

.SECONDARY:

.DELETE_ON_ERROR:

all: config.vh

config.vh: config.sv params.pl
	$(PERL) params.pl $< > $@

clean:
	rm -f config.vh
