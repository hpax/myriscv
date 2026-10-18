# Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
#!/usr/bin/make -R -r

CROSS	= $(realpath ../tools/gnu/bin)/riscv32-hpa-elf-

AS	= $(CROSS)as
LD	= $(CROSS)ld
CC	= $(CROSS)gcc
AR	= $(CROSS)ar
OBJCOPY	= $(CROSS)objcopy
PERL    = perl
HEXDUMP	= hexdump

include ../tools/riscv-opts.mk

CFLAGS  = $(riscv_flags) -nostdlib -I./include
SFLAGS  = $(CFLAGS) -D__ASSEMBLY__ -Wa,-ahlsm=$*.lst
LDFLAGS	= $(CFLAGS) -Wl,-T,test.ld -Wl,-Map=$*.map

TESTDIRS = $(wildcard tests/*)
TESTS    = $(foreach d,$(TESTDIRS),$(d)/$(notdir $(d)).elf)
TESTNAMES = $(notdir $(TESTDIRS))
gendeps = -MD -MF $(@D)/.$(@F).d -MT $@

TESTHEX  = $(TESTS:.elf=.tcm.hex) $(TESTS:.elf=.mem.hex)
BENCH    = bench

tcm_start  := 0
tcm_size   := 16384
mem_start  := 0x40000000

.SECONDARY:

.PHONY: all tests bench run $(TESTNAMES) $(addprefix run-,$(TESTNAMES))

LIB = lib/libtest.a
LIBCSRC = $(wildcard lib/*.c)
LIBSSRC = $(wildcard lib/*.S)
LIBOBJS = $(LIBCSRC:.c=.o) $(LIBSSRC:.S=.o)

all: tests

tests: $(TESTHEX)

bench:
	$(MAKE) -C $(BENCH)

run: $(addprefix run-,$(TESTNAMES))

define test-rule
$(1): tests/$(1)/$(1).tcm.hex tests/$(1)/$(1).mem.hex

run-$(1): $(1)
	$(MAKE) -C $(BENCH) run TEST=$(1) \
		TCM_INIT_FILE=$(abspath tests/$(1)/$(1).tcm.hex) \
		MEM_INIT_FILE=$(abspath tests/$(1)/$(1).mem.hex)
endef

$(foreach test,$(TESTNAMES),$(eval $(call test-rule,$(test))))

%.hex: %.bin
	$(HEXDUMP) -v -e '"" 8/4 "%08x " "\n"' $< > $@

%.tcm.bin: %.elf
	$(OBJCOPY) -O binary -R '.dram.*' $< $@

%.mem.bin: %.elf
	$(OBJCOPY) -O binary -j '.dram.*' $< $@

$(LIB): $(LIBOBJS)
	rm -f $@
	$(AR) rs $@ $^

%.elf: test.ld $(LIB)
	$(CC) $(LDFLAGS) $(LDFLAGS_$@) -o $@ $(OBJS_$@) $(LIB)

%.o: %.S
	$(CC) $(SFLAGS) $(SFLAGS_$<) $(gendeps) -c -o $@ $<

%.s: %.S
	$(CC) $(SFLAGS) $(SFLAGS_$<) $(gendeps) -E -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) $(CFLAGS_$<) $(gendeps) -c -o $@ $<

%.s: %.c
	$(CC) $(CFLAGS) $(CFLAGS_$<) $(gendeps) -S -o $@ $<

%.i: %.c
	$(CC) $(SFLAGS) $(SFLAGS_$<) $(gendeps) -E -o $@ $<

clean:
	find . $(patsubst %,-name '*%' -o,.hex .bin .elf .o .s .d .a) -false \
		| xargs -rt rm -f
	$(MAKE) -C $(BENCH) clean

tests.d: $(TESTDIRS)
	( for d in $(TESTDIRS); do \
		e="$$d/$$(basename $$d).elf" ; \
		echo -n "OBJS_$$e =" ; \
		for s in "$$d"/*.[Sc]; do \
			echo -n " $${s/%.?/.o}" ; \
		done ; \
		echo '' ; \
		echo "$$e: \$$(OBJS_$$e)" ; \
	  done ) > $@

-include tests.d
-include */.*.d
-include tests/*/*.mk
-include tests/*/.*.d
