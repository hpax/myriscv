/*
 * memset() implementation optimized for MyRISCV.
 * MyRISCV supports write combining of stores (to memory), so there is no
 * reason to try to force alignment.
 */
#include "test.h"

.macro	packb rd:req, rs1:req, rs2:req
	.insn r OP, 6, 0x04, \rd, \rs1, \rs2
.endm

begin_func memset, zeropage, global
	packb	a1, a1, a1		// byte -> word broadcast
	and	a4, a2, ~31		// Size multiple of 32 bytes
	and	a5, a2, 0x1c		// Bytes to be handled by Duff's device
	add	a3, a0, a5		// a3 is the running pointer
	neg	a5, a5
	.option push
	.option norvc
	.option	norelax
	jr	%lo(.L_bulk_entry)(a5)

	.balign	4
.L_bulk_loop:
	add	a3, a3, 32
	sw	a1, -32(a3)
	sw	a1, -28(a3)
	sw	a1, -24(a3)
	sw	a1, -20(a3)
	sw	a1, -16(a3)
	sw	a1, -12(a3)
	sw	a1,  -8(a3)
	sw	a1,  -4(a3)
.L_bulk_entry:
	bltu	a3, a4, .L_bulk_loop
	.option pop

	li	a4, 16
	baeqz	a2, a4, .L_not16
	sw	a1,   (a3)
	sw	a1,  4(a3)
	sw	a1,  8(a3)
	sw	a1, 12(a3)
	add	a3, a3, a4

.L_not16:
	li	a4, 8
	baeqz	a2, a4, .L_not8
	sw	a1,  (a3)
	sw	a1, 4(a3)
	add	a3, a3, a4
.L_not8:

	and	a2, a2, 7
	sll	a2, a2, 3
	.option push
	.option rvc
	.option norelax
	jr	%lo(.L_b0)(a2)		// Requires being in the zero page!
	.balign	8
.L_b0:
	ret
	.balign 8
.L_b1:
	sb	a1, (a3)
	ret
	.balign 8
.L_b2:
	sh	a1, (a3)
	ret
	.balign 8
.L_b3:
	sh	a1,  (a3)		// 2 bytes
	sb	a1, 2(a3)		// 4 bytes
	ret				// 2 bytes
	.balign	8
.L_b4:
	sw	a1, (a3)
	ret
	.balign	8
.L_b5:
	sw	a1,  (a3)
	sb	a1, 4(a3)
	ret
	.balign	8
.L_b6:
	sw	a1,  (a3)
	sh	a1, 4(a3)
	ret
	.balign	8
.L_b7:
	sw	a1,  (a3)
	sw	a1, 3(a3)
	ret
	.option pop

end memset
