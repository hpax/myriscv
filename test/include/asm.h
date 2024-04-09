#ifndef _ASM_H
#define _ASM_H 1

	.option arch,+zifencei

	// Warning: clobbers a0, t0, ra
	.macro print str
	.pushsection ".rodata.hot","a"
999:	.asciz "\str"
	.popsection
	la a0,999b
	call _print_str
	.endm

	// Warning: clobbers a0
	.macro print_crlf
	li a0,10
	sb a0,%lo(TTY)(zero)
	.endm
#endif /* _ASM_H */
