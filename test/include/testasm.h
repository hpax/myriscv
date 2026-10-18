/* -*- asm -*- */

#ifndef _TESTASM_H
#define _TESTASM_H 1

	.option arch,+zifencei

	// Warning: clobbers a0, t0, ra
	.macro print str:vararg
	.pushsection ".rodata.hot","a"
999:
	.ascii \str
	.byte 0
	.popsection
	la a0,999b
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

	// Branch to .Lfail unless actual equals the immediate expected value.
	// Clobbers t0.
	.macro assert_eq actual:req, expected:req
	li t0,\expected
	nop
	bne \actual,t0,.Lfail
	.endm

	// Stop the simulation with a given status
	.macro finish status=TEST_STOP
1:
	li a0,\status
	sw a0,%lo(STOP)(zero)
	j 1b
	.endm

#endif /* _TESTASM_H */
