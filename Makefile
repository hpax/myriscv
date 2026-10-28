#!/usr/bin/make -R -r

MAKEFLAGS += Rr

SUBDIRS := rtl include tools test
TARGETS := all tidy clean spotless

subtargets := $(foreach d,$(SUBDIRS),$(foreach t,$(TARGETS),$(d)/$(t)))

.DEFAULT_GOAL = all

.PHONY: $(TARGETS)
$(TARGETS):
	for d in $(SUBDIRS); do $(MAKE) $$d/$@; done

.PHONY: $(subtargets)
$(subtargets):
	$(MAKE) -C $(@D) $(@F)
