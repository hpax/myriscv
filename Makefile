#!/usr/bin/make -R -r

MAKEFLAGS += Rr

SUBDIRS := rtl include tools test
TARGETS := all tidy clean spotless

subtargets := $(foreach d,$(SUBDIRS),$(foreach t,$(TARGETS),$(d)/$(t)))

.PHONY: $(subtargets)
$(subtargets):
	$(MAKE) -C $(@D) $(@F)

.PHONY: $(TARGETS)
$(TARGETS):
	for d in $(SUBDIRS); do $(MAKE) $$d/$@; done
