#include "test.h"

	.section ".text.hot.stop","ax"
	.balign 4
	.globl stop
stop:
	li a0,TEST_STOP
	j break

	.section ".text.hot.pass","ax"
	.balign 4
	.globl pass
pass:
	li a0,TEST_PASS
	j break

	.section ".text.hot.fail","ax"
	.balign 4
	.globl fail
fail:
	li a0,TEST_FAIL
	j break

	.section ".text.hot.break","ax"
	.balign 4
	.globl break
break:
	mv s10,a0
	print "Tests done, running EBREAK.\n"
	mv a0,s10
	ebreak
	print "ERROR: fall through after EBREAK\n"
	finish TEST_FAIL

	.section ".text.hot.__assert_fail","ax"
	.balign 4
	.globl __assert_fail
__assert_fail:
	mv s0,a0
	print "Assertion failed: "
	mv a0,s0
	call _print_str
	print " in "
	mv a0,a1
	call _print_str
	print " @ "
	mv a0,a2
	call _print_str
	putc ':'
	mv a0,a3
	call _print_dec
	crlf
	finish TEST_FAIL

	.section ".text.hot.__asm_assert_fail","ax"
	.balign 4
	.globl __asm_assert_fail
__asm_assert_fail:
	mv s0,a0
	print "Assertion failed at pc "
	mv a0,s0
	call _print_hex
	mv a0,a1
	call _print_str
	print " @ "
	mv a0,a2
	call _print_str
	putc ':'
	mv a0,a3
	call _print_dec
	crlf
	finish TEST_FAIL
