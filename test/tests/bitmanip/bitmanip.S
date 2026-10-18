/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

	.section ".text.hot","ax"
	.globl __start
__start:
#if MYRISCV_WITH_Zba
	li a0,3
	li a1,10
	sh1add a2,a0,a1
	assert_eq a2,16
	sh2add a2,a0,a1
	assert_eq a2,22
	sh3add a2,a0,a1
	assert_eq a2,34
#if MYRISCV_WITH_Zbasub
	sh1sub a2,a1,a0
	assert_eq a2,17
	sh2sub a2,a1,a0
	assert_eq a2,37
	sh3sub a2,a1,a0
	assert_eq a2,77
#endif
#endif
#if MYRISCV_WITH_Zbb
	li a0,0xf0f0
	li a1,0x0ff0
	andn a2,a0,a1
	assert_eq a2,0xf000
	orn a2,a0,a1
	assert_eq a2,0xfffff0ff
	xnor a2,a0,a1
	assert_eq a2,0xffff00ff
	li a0,-1
	li a1,1
	min a2,a0,a1
	assert_eq a2,-1
	max a2,a0,a1
	assert_eq a2,1
	minu a2,a0,a1
	assert_eq a2,1
	maxu a2,a0,a1
	assert_eq a2,-1
	li a0,0x80000001
	li a1,1
	rol a2,a0,a1
	assert_eq a2,3
	ror a2,a2,a1
	assert_eq a2,0x80000001
	rori a2,a0,4
	assert_eq a2,0x18000000
	li a0,0x00120034
	orc.b a2,a0
	assert_eq a2,0x00ff00ff
	li a0,0x11223344
	rev8 a2,a0
	assert_eq a2,0x44332211
#if MYRISCV_WITH_bitcnt
	li a0,0x10
	clz a2,a0
	assert_eq a2,27
	ctz a2,a0
	assert_eq a2,4
	li a0,0xf0f0f0f0
	cpop a2,a0
	assert_eq a2,16
#endif
	li a0,0x80
	sext.b a2,a0
	assert_eq a2,0xffffff80
	li a0,0x8000
	sext.h a2,a0
	assert_eq a2,0xffff8000
	li a0,0xffff8000
	zext.h a2,a0
	assert_eq a2,0x8000
#endif

#if MYRISCV_WITH_Zbs
	li a0,0
	li a1,31
	bset a2,a0,a1
	assert_eq a2,0x80000000
	binv a2,a2,a1
	assert_eq a2,0
	li a0,-1
	bclr a2,a0,a1
	assert_eq a2,0x7fffffff
	li a0,0x10
	li a1,4
	bext a2,a0,a1
	assert_eq a2,1
	bseti a2,zero,7
	assert_eq a2,0x80
	bclri a2,a2,7
	assert_eq a2,0
	binvi a2,a2,7
	assert_eq a2,0x80
	bexti a2,a2,7
	assert_eq a2,1
#endif

#if MYRISCV_WITH_Zicond
	li a0,0x12345678
	czero.eqz a2,a0,zero
	assert_eq a2,0x12345678
	li a1,1
	czero.eqz a2,a0,a1
	assert_eq a2,0
	czero.nez a2,a0,zero
	assert_eq a2,0
	czero.nez a2,a0,a1
	assert_eq a2,0x12345678
#endif
	finish TEST_PASS
.Lfail:
	finish TEST_FAIL
