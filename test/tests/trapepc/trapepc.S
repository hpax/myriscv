/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

	.section ".init.irq","ax"
	.globl _mtvec
_mtvec:
	j .Ltrap

	.section ".text.hot","ax"
	.globl __start
__start:
	la s0,.Lbreak16
	la s1,.Ltest32
.Lbreak16:
	c.ebreak
	j .Lfail

.Ltest32:
	la s0,.Lbreak32
	ori s0,s0,1
	la s1,.Ldone
	.option push
	.option norvc
.Lbreak32:
	ebreak
	j .Lfail
	.option pop

.Ltrap:
	csrr t0,mepc
	bne t0,s0,.Lfail
	csrr t0,mcause
	li t1,MCAUSE_BREAK
	bne t0,t1,.Lfail
	jr s1

.Ldone:
	finish TEST_PASS
.Lfail:
	finish TEST_FAIL
