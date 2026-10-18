/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

	.section ".text.hot","ax"
	.globl __start
__start:
#if MYRISCV_WITH_cmpand
	li a0,0xf0
	li a1,0x0f
	baeqz a0,a1,1f
	j .Lfail
1:	li a1,0x10
	baeqz a0,a1,.Lfail
#endif

#if MYRISCV_WITH_extr
	li a0,0x12345678
	extrui a2,a0,8,8
	assert_eq a2,0x56
	extrsi a2,a0,16,8
	assert_eq a2,0x34
	li a0,0x12345680
	extrsi a2,a0,0,8
	assert_eq a2,0xffffff80
	li a1,8
	extru a2,a0,a1,8
	assert_eq a2,0x56
#endif

#if MYRISCV_WITH_extn
	li a0,0x12345678
	zexti a2,a0,8
	assert_eq a2,0x78
	li a0,0x12345680
	sexti a2,a0,8
	assert_eq a2,0xffffff80
	li a1,16
	zext a2,a0,a1
	assert_eq a2,0x5680
	sext a2,a0,a1
	assert_eq a2,0x5680
#endif

	finish TEST_PASS
.Lfail:
	finish TEST_FAIL
