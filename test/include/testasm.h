/* -*- asm -*- */

#ifndef _TESTASM_H
#define _TESTASM_H 1

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
	.option push
	.option norelax
	sb zero,%lo(TTYCHR + (\c))(zero)
	.option pop
.endm
.macro crlf
	putc 10
.endm
.macro putcr r:req
	.option push
	.option norelax
	sb \r,%lo(TTY)(zero)
	.option pop
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
	mv a3,\actual
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
.macro finishr reg:req
	.option push
	.option norelax
	sw \reg,%lo(STOP)(zero)
	.option pop
	li a0,-1
1:	wfi zero, a0
	j 1b
.endm
.macro finish status=TEST_STOP
1:
	li a0,\status
	finishr a0
.endm

#endif /* _TESTASM_H */
