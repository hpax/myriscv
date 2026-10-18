#include "test.h"

	.section ".text.hot","ax"
	.globl __start
__start:
	la a0,hello_str
	lbu a1,(a0)
	beqz a1,2f
1:
	add a0,a0,1
	sb a1,-1(zero)
	lbu a1,(a0)
	bnez a1,1b

2:
	li a0,TEST_STOP
	ebreak
	j 2b

	.section ".rodata.hot","a"
hello_str:
	.asciz "Hello, World!\r\n"
