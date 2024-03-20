#!/usr/bin/make -R -r

CROSS	= riscv32-unknown-elf-

AS	= $(CROSS)as
LD	= $(CROSS)ld
CC	= $(CROSS)gcc
OBJCOPY	= $(CROSS)objcopy
PERL    = perl
HEXDUMP	= hexdump

# gcc seems to not understand Zmmul, but adding m and -mno-div works...
CFLAGS  = -march=rv32imc_zba_zbb_zbs_zicond_zicsr_zmmul -mabi=ilp32 \
	 -mno-strict-align -mbranch-cost=2 \
	-fno-exceptions -malign-data=natural -fshort-enums -fshort-wchar \
	-fno-pic -fno-pie -frename-registers -ftls-model=local-exec \
	-mno-div -O3 -ggdb3
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
