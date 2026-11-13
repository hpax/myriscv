/*
 * Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
 *
 * memcpy() and mempcpy() for MyRISCV.
 *
 * Aligning the source allows the main loop to use single-transaction loads.
 * Stores may remain unaligned: sequential stores can be combined by the
 * load/store unit.
 */
#include "test.h"

begin_func mempcpy, hot, global
	add	t0, a0, a2
	j	.L_copy
end mempcpy

begin_func memcpy, hot, global
	mv	t0, a0

.L_copy:
	beqz	a2, .L_done

	andi	t1, a1, 3
	beqz	t1, .L_words

	li	t2, 4
	sub	t1, t2, t1
	bltu	a2, t1, .L_tail
.L_align:
	lbu	t2, (a1)
	sb	t2, (a0)
	addi	a1, a1, 1
	addi	a0, a0, 1
	addi	a2, a2, -1
	addi	t1, t1, -1
	bnez	t1, .L_align
	beqz	a2, .L_done

.L_words:
	li	t1, 16
	bltu	a2, t1, .L_tail

	.balign	4
.L_word_loop:
	lw	a3,  (a1)
	lw	a4,  4(a1)
	lw	a5,  8(a1)
	lw	a6, 12(a1)
	sw	a3,  (a0)
	sw	a4,  4(a0)
	sw	a5,  8(a0)
	sw	a6, 12(a0)
	addi	a1, a1, 16
	addi	a0, a0, 16
	addi	a2, a2, -16
	bgeu	a2, t1, .L_word_loop

.L_tail:
	li	t1, 4
	bltu	a2, t1, .L_byte_tail
	lw	a3, (a1)
	sw	a3, (a0)
	addi	a1, a1, 4
	addi	a0, a0, 4
	addi	a2, a2, -4
	j	.L_tail

.L_byte_tail:
	beqz	a2, .L_done
.L_byte_loop:
	lbu	t1, (a1)
	sb	t1, (a0)
	addi	a1, a1, 1
	addi	a0, a0, 1
	addi	a2, a2, -1
	bnez	a2, .L_byte_loop

.L_done:
	mv	a0, t0
	ret
end memcpy
