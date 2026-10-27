#!/usr/bin/make -R -r

MAKEFLAGS += Rr

SUBDIRS = rtl include tools test

%.all %.tidy %.clean %.spotless:
	$(MAKE) -C $* $(suffix $@)

all tidy clean spotless:
	for $$d in $(SUBDIRS); do $(MAKE) $$d.$@; done
