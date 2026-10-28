	#include "test.h"

	.section ".text.hot","ax"
	.globl __start
__start:
	la a0,la_string
	jal _print_str
	lai a0,lai_string
	jal _print_str

	finish TEST_STOP

	.section ".rodata.hot","a"
	.balign 2
la_string:
	.asciz "Using la\n\0"
	.balign 2
lai_string:
	.asciz "Using lai\n\0"
