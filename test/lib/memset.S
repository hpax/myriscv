/*
 * Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com>
 *
 * memset() for MyRISCV.
 *
 * Sequential stores may remain unaligned: the load/store unit combines
 * their overlapping bus fragments when possible.
 */
#include "test.h"

begin_func memset, hot, global
	mv	t0, a0
	andi	a1, a1, 0xff
	slli	t1, a1, 8
	or	a1, a1, t1
	slli	t1, a1, 16
	or	a1, a1, t1

	li	t1, 16
	bltu	a2, t1, .L_tail

	.balign	4
.L_word_loop:
	sw	a1,  (a0)
	sw	a1,  4(a0)
	sw	a1,  8(a0)
	sw	a1, 12(a0)
	addi	a0, a0, 16
	addi	a2, a2, -16
	bgeu	a2, t1, .L_word_loop

.L_tail:
	li	t1, 4
	bltu	a2, t1, .L_short_tail
	sw	a1, (a0)
	addi	a0, a0, 4
	addi	a2, a2, -4
	j	.L_tail

.L_short_tail:
	li	t1, 2
	bltu	a2, t1, .L_byte_tail
	sh	a1, (a0)
	addi	a0, a0, 2
	addi	a2, a2, -2

.L_byte_tail:
	beqz	a2, .L_done
	sb	a1, (a0)

.L_done:
	mv	a0, t0
	ret
end memset
