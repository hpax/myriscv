	.option arch,rv32imc
	.option arch,+zba
	.option arch,+zbb
	.option arch,+zbs

	.section ".null","a"
	.balign 4
	.globl ___NULL
___NULL:
	.word 0

	.section ".init.reset","ax"
	.balign 4
	.globl ___reset
___reset:
	.option push
	.option norelax
	la sp, ___stack_top
	la gp, __global_pointer$
	.option pop
	.option push
	j _start

	.section ".text.hot","ax"
_start:
	la a0,hello_str
	lbu a1,(a0)
	beqz a1,2f
1:
	add a0,a0,1
	sb a1,-1(zero)
	lbu a1,(a0)
	bnez a1,1b

2:
	ebreak
	j 2b

	.section ".rodata.hot","a"
hello_str:
	.asciz "Hello, World!\r\n"

	.section ".stack","a"
	.balign 16
	.globl ___stack
	.globl ___stack_top
___stack:
	.space 2048
___stack_top:
