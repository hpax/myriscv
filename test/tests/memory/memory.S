/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

	.section ".text.hot","ax"
	.globl __start
__start:
	la a0,data
	li a1,0x11223344
	sw a1,0(a0)
	fence rw,rw

#if MYRISCV_WITH_Zalrsc
	lr.w a2,(a0)
	assert_eq a2,0x11223344
	li a1,0x55667788
	sc.w a2,a1,(a0)
	assert_eq a2,0
	lw a2,0(a0)
	assert_eq a2,0x55667788

#endif
	/* Sequential misaligned stores should preserve every byte. */
	li a1,0x11223344
	li a2,0x55667788
	sw a1,1(a0)
	sw a2,5(a0)
	fence rw,rw
	lw a3,0(a0)
	assert_eq a3,0x22334444
	lw a3,4(a0)
	assert_eq a3,0x66778811
	lw a3,8(a0)
	assert_eq a3,0x00000055

	cbo.clean (a0)
	cbo.inval (a0)
	cbo.flush (a0)
	fence.i
	finish TEST_PASS
.Lfail:
	finish TEST_FAIL

	.section ".sdata","aw"
	.balign 4
data:
	.word 0, 0, 0
