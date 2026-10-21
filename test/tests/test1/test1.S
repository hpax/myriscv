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

	/* Try to print a series of decimal numbers (2*powers of 7) */
	li a0,2
	li s1,3954653486	/* 2*7^11 */
	j .L_first_num

.L_pwr:
	sll a0,s0,3
	sub a0,a0,s0

.L_first_num:
	mv s0,a0
	call _print_dec
	crlf
	bltu s0,s1,.L_pwr

2:
	li a0,TEST_STOP
	ebreak
	j 2b

	.section ".rodata.hot","a"
hello_str:
	.asciz "Hello, World!\n"
