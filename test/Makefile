#!/usr/bin/make -R -r

CROSS	= riscv32-unknown-elf-

AS	= $(CROSS)as
LD	= $(CROSS)ld
CC	= $(CROSS)gcc
OBJCOPY	= $(CROSS)objcopy
PERL    = perl
HEXDUMP	= hexdump

CFLAGS  = -march=rv32imc -O2 -ggdb3
ASFLAGS = -D__ASSEMBLY__
LDFLAGS	= -T test.ld

.SECONDARY:

all: test1.hex test2.hex

%.hex: %.bin
	$(HEXDUMP) -v -e '"" 8/4 "%08x " "\n"' $< > $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.elf: %.o test.ld
	$(LD) $(LDFLAGS) -o $@ $<

%.o: %.S
	$(CC) $(ASFLAGS) -c -o $@ $<
