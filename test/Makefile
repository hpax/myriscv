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

# gcc seems to not understand Zmmul, but adding m and -mno-div works...
CFLAGS  = $(riscv_flags) -I./include
SFLAGS  = $(CFLAGS) -D__ASSEMBLY__ -Wa,-ahlsm=$*.lst
LDFLAGS	= $(CFLAGS) -Wl,-T,test.ld -Wl,-Map=$*.map

TESTDIRS = $(wildcard tests/*)
TESTS    = $(foreach d,$(TESTDIRS),$(d)/$(notdir $(d)).elf)
gendeps = -MD -MF $(@D)/.$(@F).d -MT $@

TESTHEX  = $(TESTS:.elf=.tcm.hex) $(TESTS:.elf=.mem.hex)

tcm_start  := 0
tcm_size   := 16384
mem_start  := 0x40000000

.SECONDARY:

LIB = lib/libtest.a
LIBCSRC = $(wildcard lib/*.c)
LIBSSRC = $(wildcard lib/*.S)
LIBOBJS = $(LIBCSRC:.c=.o) $(LIBSSRC:.S=.o)

all: $(TESTHEX)

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

%.o: %.c
	$(CC) $(CFLAGS) $(CFLAGS_$<) $(gendeps) -c -o $@ $<

%.s: %.c
	$(CC) $(CFLAGS) $(CFLAGS_$<) $(gendeps) -S -o $@ $<

clean:
	find . $(patsubst %,-name '*%' -o,.hex .bin .elf .o .s .d .a) -false \
		| xargs -rt rm -f

tests.d:
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
-include tests/*/*.mk
-include tests/*/.*.d
