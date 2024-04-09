#include "asm.h"

	.section ".text.hot.print_str","ax"
	.globl _print_str
	.balign 4
_print_str:
	lbu t0,(a0)
	add a0,a0,1
	beqz t0,2f
1:
	sb t0,%lo(TTY)(zero)
	lbu t0,(a0)
	add a0,a0,1
	bnez t0,1b
2:
	ret

	.section ".text.hot.print_hex","ax"
	.globl _print_hex
	.balign 4
_print_hex:
	add sp,sp,-32
	sw a1,(sp)
	sw a2,4(sp)
	sw a3,8(sp)
	sw a4,12(sp)
	sw a5,16(sp)

	li a1,8
	li a4,0x61
	li a5,0x30-(0x61-10)
1:
	ror a0,a0,32-4
	and a2,a0,15
	add a2,a2,0x61-10
#if 0
	bgeu a2,a4,2f
	add a2,a2,a5
2:
#else
	sltu a3,a2,a4
	czero.eqz a3,a5,a3
	add a2,a2,a3
#endif
	sb a2,%lo(TTY)(zero)
	add a1,a1,-1
	bnez a1,1b

	lw a1,(sp)
	lw a2,4(sp)
	lw a3,8(sp)
	lw a4,12(sp)
	lw a5,16(sp)
	add sp,sp,16

	ret

	.section ".text.hot.print_crlf","ax"
	.globl _print_crlf
	.balign 4
_print_crlf:
	li a0,10
	sw a0,%lo(TTY)(zero)
	ret
