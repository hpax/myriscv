/* -*- asm -*- */

#ifndef _TESTASM_H
#define _TESTASM_H 1

	.option arch,+zifencei

	// Warning: clobbers a0, t0, ra
	.macro print str:vararg
	.pushsection .rodata.hot.str1.1, "aMS", @progbits, 1
979:
	.ascii \str
	.byte 0
	.popsection
	la a0,979b
	call _print_str
	.endm

	// These do not clobber any registers at all!
	.macro putc c:req
	sb zero,%lo(TTYCHR + (\c))(zero)
	.endm
	.macro crlf
	putc 10
	.endm
	.macro putcr r:req
	sb \r,%lo(TTY)(zero)
	.endm

	// Print an assertion failure message and then aborts if
	// register doesn't match the value of "expected".
	// Clobbers t0
#define assert_eq _assert_eq __FILE__, __LINE__,
	.macro _assert_eq file:req, line:req, actual:req, expected:req
970:
	li t0,\expected
	bne \actual,t0,972f

	.subsection 1
972:
	la a0,970b
	la a1,971f
	li a2,\line
	j __asm_assert_fail
	.previous
	.pushsection ".rodata.hot.str1.1", "aMS", @progbits, 1
971:
	.asciz "\file"
	.popsection
	.endm

	// Stop the simulation with a given status
	.macro finish status=TEST_STOP
1:
	li a0,\status
	sw a0,%lo(STOP)(zero)
	j 1b
	.endm

#endif /* _TESTASM_H */
