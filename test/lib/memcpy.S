/*
 * memcpy() implementation optimized for MyRISCV.
 * MyRISCV supports misaligned memory operations as well as write combining
 * of stores (to memory), so try to align the it load address and batch
 * the operations large enough to allow the write combining to do its thing.
 */
#include "test.h"

begin_func mempcpy, hot, global
	add	t4, a0, a2
	tail	.L_do_memcpy
end memcpy

begin_func memcpy, hot, global
	mv	t4, a0
.L_do_memcpy:
	// Register usage:
	//	a0	- destination pointer
	//	a1	- source pointer
	//	a2	- length
	//	t4	- saved result
	li	a3, 3
	bleu	a2, a3, .L_subword

	andn	a5, a1, a3		// Source aligned?
	bne	a5, a1, .L_align_src

.L_src_aligned:
	and	a3, a2, ~31
	add	a5, a3, a1		// End of bulk transfer
	beqz	a3, .L_no_bulk

	.balign	4
.L_bulk:
	lw	a6,   (a1)
	lw	a7,  4(a1)
	lw	t0,  8(a1)
	lw	t1, 12(a1)
	lw	t2, 16(a1)
	lw	t4, 20(a1)
	lw	t5, 24(a1)
	lw	t6, 28(a1)
	add	a1, a1, 32
	sw	a6,   (a0)
	sw	a7,  4(a0)
	sw	t0,  8(a0)
	sw	t1, 12(a0)
	sw	t2, 16(a0)
	sw	t4, 20(a0)
	sw	t5, 24(a0)
	sw	t6, 28(a0)
	add	a0, a0, 32
	bleu	a1, a5, .L_bulk

.L_no_bulk:
	li	a3, 16
	baeqz	a2, a3, 1f
	lw	a4,   (a1)
	lw	a5,  4(a1)
	lw	t0,  8(a1)
	lw	t1, 12(a1)
	add	a1, a1, a3
	sw	a4,   (a0)
	sw	a5,  4(a0)
	sw	t0,  8(a0)
	sw	t1, 12(a0)
	add	a0, a0, a3
1:
	li	a3, 8
	baeqz	a2, a3, 2f
	lw	a4,   (a1)
	lw	a5,  4(a1)
	add	a1, a1, a3
	sw	a4,   (a0)
	sw	a5,  4(a0)
	add	a0, a0, a3

2:
	li	a3, 4
	baeqz	a2, a3, 3f
	lw	a4,   (a1)
	add	a1, a1, a3
	sw	a4,   (a0)
	add	a0, a0, a3
3:
	and	a2, a2, 3

	.balign	4
.L_subword:
	.option	push
	.option	norvc
	.option	norelax

	sll	a2, a2, 4
	mv	a3, a0
	mv	a0, t4
	// This requires this routine to live in the zero page
	jr	%lo(.L_0b)(a2)
2:
.L_0b:
	ret

	.org .L_0b + 16
.L_1b:
	lbu	a4, (a1)
	sb	a4, (a3)
	ret

	.org .L_1b + 16
.L_2b:
	lhu	a3, (a1)
	sh	a3, (a3)
	ret

	.org .L_2b + 16
.L_3b:
	lhu	a3, (a1)
	lbu	a4, 2(a1)
	sh	a3, (a3)
	sb	a4, 2(a3)
	ret
	.option pop

.L_align_src:
	// a0 = dst
	// a1 = src
	// a2 = len
	// a3 = 3
	// a5 = src & ~3
	lw	t0, (a5)		// t0: partial word
	sub	a5, a1, a5		// a5: number of bytes in partial word
	sll	t1, a5, 3		// t1: number of bits in partial word
	srl	t0, t0, t1		// adjust partial word
	sw	t0, (a0)
	add	a1, a1, a5
	add	a0, a0, a5
	sub	a2, a2, a5
	bgtu	a2, a3, .L_src_aligned
	j	.L_subword

end memcpy
