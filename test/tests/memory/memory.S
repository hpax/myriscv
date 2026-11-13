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

	/* memcpy() preserves guards around an unaligned 37-byte copy. */
	la a0,copy_dst
	addi a0,a0,1
	la a1,copy_src
	addi a1,a1,1
	li a2,37
	call memcpy
	la a4,copy_dst
	addi a4,a4,1
	sub a3,a0,a4
	assert_eq a3,0
	lbu a3,-1(a4)
	assert_eq a3,0xaa
	lbu a3,0(a4)
	assert_eq a3,1
	lbu a3,15(a4)
	assert_eq a3,16
	lbu a3,36(a4)
	assert_eq a3,37
	lbu a3,37(a4)
	assert_eq a3,0xaa

	/* mempcpy() returns the end of the copied range. */
	la a0,copy_dst
	addi a0,a0,3
	la a1,copy_src
	addi a1,a1,2
	li a2,5
	call mempcpy
	la a4,copy_dst
	addi a4,a4,8
	sub a3,a0,a4
	assert_eq a3,0
	lbu a3,-5(a4)
	assert_eq a3,2
	lbu a3,-1(a4)
	assert_eq a3,6

	/* A short copy must not overrun its source-alignment prefix. */
	la a0,copy_dst
	addi a0,a0,20
	la a1,copy_src
	addi a1,a1,1
	li a2,1
	call memcpy
	la a4,copy_dst
	addi a4,a4,20
	sub a3,a0,a4
	assert_eq a3,0
	lbu a3,0(a4)
	assert_eq a3,1

	/* memset() preserves guards around an unaligned 37-byte fill. */
	la a0,set_dst
	addi a0,a0,1
	li a1,0x5a
	li a2,37
	call memset
	la a4,set_dst
	addi a4,a4,1
	sub a3,a0,a4
	assert_eq a3,0
	lbu a3,-1(a4)
	assert_eq a3,0xaa
	lbu a3,0(a4)
	assert_eq a3,0x5a
	lbu a3,36(a4)
	assert_eq a3,0x5a
	lbu a3,37(a4)
	assert_eq a3,0xaa

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

	.balign 4
copy_src:
	.byte 0, 1, 2, 3, 4, 5, 6, 7
	.byte 8, 9, 10, 11, 12, 13, 14, 15
	.byte 16, 17, 18, 19, 20, 21, 22, 23
	.byte 24, 25, 26, 27, 28, 29, 30, 31
	.byte 32, 33, 34, 35, 36, 37, 38, 39

	.balign 4
copy_dst:
	.byte 0xaa
	.space 37
	.byte 0xaa

	.balign 4
set_dst:
	.byte 0xaa
	.space 37
	.byte 0xaa
