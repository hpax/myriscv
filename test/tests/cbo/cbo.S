/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

	.section ".text.hot","ax"
	.option norvc
	.globl __start
__start:
	/* A cold store forces the following clean through lookup replay. */
	li s0,0x40000000
	li t0,0x80824531		/* li a0,12; ret */
	sw t0,0(s0)
	cbo.clean (s0)
	fence.i
	jalr ra,0(s0)
	li t0,12
	bne a0,t0,.Lfail

	li t0,0x12345678
	addi s1,s0,4
	sw t0,0(s1)
	cbo.flush (s1)
	fence.i
	lw t1,4(s0)
	nop
	nop
	bne t0,t1,.Lfail

	/* Invalidate must discard dirty data without overwriting memory. */
	li t2,0x87654321
	sw t2,4(s0)
	cbo.inval (s1)
	fence.i
	lw t1,4(s0)
	nop
	nop
	bne t0,t1,.Lfail
	finish TEST_PASS

.Lfail:
	finish TEST_FAIL
