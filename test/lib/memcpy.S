#include "asm.h"

.macro do_memcpy end:req
	.option	push
	.option	norvc
	andi	a5, a2, 7 << 3
	add	a1, a1, a5
	add	a3, a0, a5
	neg	a5, a5
	add	\end, a0, a2
	add	t2, a1, a2
	.option push
	.option norelax
	jr	%lo(.L\@_loop_end)(a5)
	.option pop

	.balign	4
.L\@_loop_start:
	offs = -64
	.rept 8
	lw	t0, offs(a1)
	lw	t1, (offs+4)(a1)
	sw	t0, offs(a3)
	sw	t1, (offs+4)(a3)
	offs = offs + 8
	.endr
.L\@_loop_end:
	add	a1, a1, 64
	add	a3, a3, 64
	bleu	a3, \end, .L\@_loop_start

	andi	a5, a2, 7
	beqz	a5, .L\@_notail
	add	a5, a5, a3
.L\@_tail_loop:
	lbu	t0, -64(a1)
	addi	a1, a1, 1
	sb	t0, -64(a3)
	addi	a3, a3, 1
	bltu	a3, a5, .L\@_tail_loop
.L\@_notail:
	.option pop
.endm

begin_func mempcpy, zeropage, global
	do_memcpy end=a0
	ret
end mempcpy

begin_func memcpy, zeropage, global
	do_memcpy end=a4
	ret
end memcpy
