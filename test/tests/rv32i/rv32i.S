/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

	.section ".text.hot","ax"
	.globl __start
__start:
	li a0,0x12345678
	li a1,0x11111111
	add a2,a0,a1
	assert_eq a2,0x23456789
	sub a2,a0,a1
	assert_eq a2,0x01234567
	li a1,4
	sll a2,a0,a1
	assert_eq a2,0x23456780
	li a1,0x11111111
	slt a2,zero,a0
	assert_eq a2,1
	sltu a2,a0,zero
	assert_eq a2,0
	xor a2,a0,a1
	assert_eq a2,0x03254769
	li a1,4
	srl a2,a0,a1
	assert_eq a2,0x01234567
	sra a2,a0,a1
	assert_eq a2,0x01234567
	li a1,0x11111111
	or a2,a0,a1
	assert_eq a2,0x13355779
	and a2,a0,a1
	assert_eq a2,0x10101010

	addi a2,a0,-1
	assert_eq a2,0x12345677
	slti a2,a0,1
	assert_eq a2,0
	sltiu a2,a0,-1
	assert_eq a2,1
	xori a2,a0,-1
	assert_eq a2,0xedcba987
	ori a2,a0,0x55
	assert_eq a2,0x1234567d
	andi a2,a0,0x5a5
	assert_eq a2,0x00000420
	slli a2,a0,4
	assert_eq a2,0x23456780
	srli a2,a0,4
	assert_eq a2,0x01234567
	srai a2,a0,4
	assert_eq a2,0x01234567

	beq a0,a0,1f
	j .Lfail
1:	bne a0,a1,1f
	j .Lfail
1:	blt zero,a0,1f
	j .Lfail
1:	bge a0,zero,1f
	j .Lfail
1:	bltu zero,a0,1f
	j .Lfail
1:	bgeu a0,zero,1f
	j .Lfail
1:
	lui a2,0x12345
	assert_eq a2,0x12345000
	auipc a2,0
	beqz a2,.Lfail
	jal ra,1f
	j 2f
1:	jalr zero,0(ra)
2:

	la a3,data
	lb a2,0(a3)
	assert_eq a2,0xffffff80
	lbu a2,1(a3)
	assert_eq a2,0x7f
	lh a2,2(a3)
	assert_eq a2,0xffff8000
	lhu a2,2(a3)
	assert_eq a2,0x8000
	lw a2,4(a3)
	assert_eq a2,0x89abcdef
	li a2,0x5a
	sb a2,8(a3)
	lbu a2,8(a3)
	assert_eq a2,0x5a
	li a2,0x5678
	sh a2,10(a3)
	lhu a2,10(a3)
	assert_eq a2,0x5678
	li a2,0x12345678
	sw a2,12(a3)
	lw a2,12(a3)
	assert_eq a2,0x12345678

#if MYRISCV_WITH_Zmmul
	li a0,0x80000000
	li a1,2
	mul a2,a0,a1
	assert_eq a2,0
	mulh a2,a0,a1
	assert_eq a2,0xffffffff
	mulhsu a2,a0,a1
	assert_eq a2,0xffffffff
	mulhu a2,a0,a1
	assert_eq a2,1
#endif
#if MYRISCV_CTR_TIME_WIDTH || MYRISCV_CTR_CYCLE_WIDTH
	rdcycle a0
	rdcycle a1
	bltu a1,a0,.Lfail
#endif
#if MYRISCV_WITH_regcsr
	li a0,0x13579bdf
	csrrw a1,mscratch,a0
	csrr a1,mscratch
	assert_eq a1,0x13579bdf
	li a0,0x20
	csrrs a1,mscratch,a0
	assert_eq a1,0x13579bdf
	csrr a1,mscratch
	assert_eq a1,0x13579bff
#endif

	finish TEST_PASS
.Lfail:
	finish TEST_FAIL

	.section ".sdata","aw"
	.balign 4
data:
	.byte 0x80,0x7f
	.half 0x8000
	.word 0x89abcdef
	.word 0
	.word 0
