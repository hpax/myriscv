/* -*- ld-script -*-
 *
 * Linker script simple embedded RISCV
 */

OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv",
              "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_reset)
EXTERN(_NULL)
EXTERN(_reset)
EXTERN(_mtvec)

MEMORY
{
	SRAM	: org = 0x00000000, len = 0x4000
	DRAM	: org = 0x40000000, len = 0x100000
}

SECTIONS
{
	/* Debugging sections */
  /* Stabs debugging sections.  */
  .stab          0 : { *(.stab) }
  .stabstr       0 : { *(.stabstr) }
  .stab.excl     0 : { *(.stab.excl) }
  .stab.exclstr  0 : { *(.stab.exclstr) }
  .stab.index    0 : { *(.stab.index) }
  .stab.indexstr 0 : { *(.stab.indexstr) }
  .comment       0 : { *(.comment) }
  .gnu.build.attributes : { *(.gnu.build.attributes .gnu.build.attributes.*) }
  /* DWARF debug sections.
     Symbols in the DWARF debugging sections are relative to the beginning
     of the section so we begin them at 0.  */
  /* DWARF 1.  */
  .debug          0 : { *(.debug) }
  .line           0 : { *(.line) }
  /* GNU DWARF 1 extensions.  */
  .debug_srcinfo  0 : { *(.debug_srcinfo) }
  .debug_sfnames  0 : { *(.debug_sfnames) }
  /* DWARF 1.1 and DWARF 2.  */
  .debug_aranges  0 : { *(.debug_aranges) }
  .debug_pubnames 0 : { *(.debug_pubnames) }
  /* DWARF 2.  */
  .debug_info     0 : { *(.debug_info .gnu.linkonce.wi.*) }
  .debug_abbrev   0 : { *(.debug_abbrev) }
  .debug_line     0 : { *(.debug_line .debug_line.* .debug_line_end) }
  .debug_frame    0 : { *(.debug_frame) }
  .debug_str      0 : { *(.debug_str) }
  .debug_loc      0 : { *(.debug_loc) }
  .debug_macinfo  0 : { *(.debug_macinfo) }
  /* SGI/MIPS DWARF 2 extensions.  */
  .debug_weaknames 0 : { *(.debug_weaknames) }
  .debug_funcnames 0 : { *(.debug_funcnames) }
  .debug_typenames 0 : { *(.debug_typenames) }
  .debug_varnames  0 : { *(.debug_varnames) }
  /* DWARF 3.  */
  .debug_pubtypes 0 : { *(.debug_pubtypes) }
  .debug_ranges   0 : { *(.debug_ranges) }
  /* DWARF 5.  */
  .debug_addr     0 : { *(.debug_addr) }
  .debug_line_str 0 : { *(.debug_line_str) }
  .debug_loclists 0 : { *(.debug_loclists) }
  .debug_macro    0 : { *(.debug_macro) }
  .debug_names    0 : { *(.debug_names) }
  .debug_rnglists 0 : { *(.debug_rnglists) }
  .debug_str_offsets 0 : { *(.debug_str_offsets) }
  .debug_sup      0 : { *(.debug_sup) }
  .gnu.attributes 0 : { KEEP (*(.gnu.attributes)) }
  .riscv.attributes 0 : { KEEP(*(.riscv.attributes)) }

	/*
	 * Sections we do not need. This program cannot exit, so
	 * fini/destructors are never needed. Exception handling
	 * is not supported.
	 */
	 /DISCARD/	: {
		*(.note.GNU-stack)
		*(.gnu_debuglink)
		*(.gnu.lto_*)
		*(.discard)
		*(.discard.*)
		*(.dtors.*)
		*(.dtors)
		*(.fini_array)
		*(.fini_array.*)
		*(.gcc_except_table .gcc_except_table.*)
		*(.gnu_extab*)
		*(.exception_ranges*)
		*(.text.exit .text.exit.*)
		*(.eh_frame .eh_frame.*)
		*crtbegin.o(*)
		*crt0.o(*)
	}

	. = 0;
	PROVIDE (__executable_start = .);

	/*
	 * Make sure the output binary starts at address 0
	 */
	.null 0 : {
		PROVIDE(___NULL = .);
		KEEP (*(SORT_NONE(.null)))
	} >SRAM

	.init.reset 0x10 : ALIGN(4) {
		PROVIDE (___reset = .);
		KEEP (*(SORT_NONE(.init.reset)))
	} >SRAM

	.init.irq 0x80 : ALIGN(4) {
		PROVIDE (___mtvec = .);
		KEEP (*(SORT_NONE(.init.irq)))
	} >SRAM

	.init : ALIGN(4) {
		KEEP (*(SORT_NONE(.init .init.*)))
	} >SRAM

	.text.zeropage : ALIGN(4) {
		*(.text.zeropage *.text.zeropage.*)
	} >SRAM

	/* .rwtext is in the zero page */
	.rwtext : ALIGN(4) {
		PROVIDE (__rwtext_start = .);
		*(.rwtext*)
		PROVIDE (__rwtext_end = .);
	} >SRAM

	/*
	 * Put the short data sections in the zero page.
	 * This means the initialized sections aren't contiguous, but
	 * all memory is intialized during FPGA load anyway.
	 */
	. = ALIGN(4);
	__SDATA_BEGIN__ = .;
	.srodata : {
		*(.srodata*)
	} >SRAM
	.sdata : {
		*(.sdata .sdata.* .gnu.linkonce.s.*)
	} >SRAM
	.sdata2 : {
		*(.sdata2 .sdata2.* .gnu.linkonce.s2.*)
	} >SRAM

	. = ALIGN(32);
	__BSS_START__ = .;
	PROVIDE (__bss_start = .);
	.sbss (NOLOAD) : ALIGN(4) {
		*(.dynsbss)
		*(.sbss .sbss.* .gnu.linkonce.sb.*)
		*(.scommon)
	} >SRAM
	.sbss2 (NOLOAD) : {
	       *(.sbss2 .sbss2.* .gnu.linkonce.sb2.*)
	} >SRAM

	HIDDEN($assert_zero_page = ASSERT((. <= 2048), "zero page overflow"));

	.bss (NOLOAD) : {
		*(.dynbss)
		*(.bss.*hot* .gnu.linkonce.b.*)
		*(COMMON)
	} >SRAM
	. = ALIGN(32);
	__BSS_END__ = .;
	__BSS_LEN__ = __BSS_END__ - __BSS_START__;

	/* For the stuff immediately outside the zero page */
	__global_pointer$ = 0x800;

	PROVIDE(___text = .);

	.init : ALIGN(4) {
		KEEP (*(SORT_NONE(.init)))
	} >SRAM

	.text.hot : ALIGN(4) {
		*(.text.startup .text.startup.*)
		*(.text.hot .text.hot.*)
		*(.gnu.linkonce.t.*)
	} >SRAM
	PROVIDE (__etext = .);
	PROVIDE (_etext = .);

	. = ALIGN(4);
	.str.hot : ALIGN(4) {
		*(.rodata*.hot.str*)
	} >SRAM
	.rodata.hot         : {
		*(.rodata*.hot* .gnu.linkonce.r.*)
	} >SRAM

	/* Thread Local Storage sections  */
	.tdata          : {
		PROVIDE_HIDDEN (__tdata_start = .);
		*(.tdata .tdata.* .gnu.linkonce.td.*)
	} >SRAM
	.tbss       : { *(.tbss .tbss.* .gnu.linkonce.tb.*) *(.tcommon) } >SRAM
	.preinit_array    : {
		PROVIDE_HIDDEN (__preinit_array_start = .);
		KEEP (*(.preinit_array))
		PROVIDE_HIDDEN (__preinit_array_end = .);
	} >SRAM
	/* Are these necessary/supportable? */
	  .jcr          : { KEEP (*(.jcr)) } >SRAM
	.data.rel.ro	: {
			*(.data.rel.ro.local* .gnu.linkonce.d.rel.ro.local.*)
			*(.data.rel.ro .data.rel.ro.* .gnu.linkonce.d.rel.ro.*)
	} >SRAM

	.data           : {
		__DATA_BEGIN__ = .;
		*(.data .data.* .gnu.linkonce.d.*)
		SORT(CONSTRUCTORS)
	} >SRAM
	.data1          : { *(.data1) }
	_edata = .;
	_end = .;

	.stack (NOLOAD) : ALIGN(16) {
		KEEP (*(.stack))
	} >SRAM

	/* Sections in SDRAM */
	. = 0x40000000;
	__dram_start = .;

	. = ALIGN(4096);	/* Align to a flash page */
	__dram_init_start = .;

	.dram.text : ALIGN(4) {
		*(SORT(.text.sorted.*))
		*(.text .stub .text.*)
		*(.text.*unlikely*)
		*(.dram.text*)
	} >DRAM

	.dram.str : ALIGN(4) {
		__dram_str_start = .;
		*(.rodata*.str* .dram.rodata*.str*)
		__dram_str_end = .;
	} >DRAM

	.dram.rodata : ALIGN(4) {
		__dram_rodata_start = .;
		*(.rodata* .dram.rodata*)
		__dram_rodata_end = .;
	} >DRAM

	.eh_frame : ALIGN(4) {
		*(.eh_frame_hdr) *(.eh_frame_entry .eh_frame_entry.*)
		*(.eh_frame) *(.eh_frame.*)
	} >DRAM

	.dram.init_array : ALIGN(4) {
		PROVIDE_HIDDEN (__init_array_start = .);
		KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*)
		SORT_BY_INIT_PRIORITY(.ctors.*)))
		KEEP (*(.init_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .ctors))
		PROVIDE_HIDDEN (__init_array_end = .);
	} >DRAM

	.dram.data : ALIGN(4) {
		*(.dram.data* .data*)
	} >DRAM

	. = ALIGN(8);
	__dram_init_end = .;
	__dram_init_len = __dram_init_end - __dram_init_start;

	/* bss can overlay the test program image */
	. = __dram_init_end;

	__dram_bss_start = .;
	.dram.bss (NOLOAD) : ALIGN(8) {
		*(.dram.bss* .bss*)
	} >DRAM
	. = ALIGN(8);
	__dram_bss_end = .;
	__dram_bss_len = __dram_bss_end - __dram_bss_start;

	/* Like BSS except no need to clear on boot */
	.dram.noinit (NOLOAD) : ALIGN(8) {
		*(.dram.noinit*)
	} >DRAM

	__dram_end = .;

/*	HIDDEN($assert_no_junk = ASSERT(__junk_end == __junk_start, "unknown sections present")); */
}
