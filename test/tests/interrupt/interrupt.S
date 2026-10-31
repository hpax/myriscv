/* Copyright (C) 2026 H. Peter Anvin <hpa@zytor.com> */
#include "test.h"

#define IRQ_LEVEL	1
#define IRQ_WFI_MASKED	2
#define IRQ_WFI_WAKE	4
#define IRQ_EDGE	3

#define IRQ_BIT(irq)	(1 << (irq))
#define IRQ_EDGE_MASK	-1024
#define IRQ_TIMER(irq)	(-1024 + 4 * (irq))

	.macro delay cycles:req
	li t0,\cycles
.Ldelay\@:
	addi t0,t0,-1
	bnez t0,.Ldelay\@
	.endm

	.section ".init.irq","ax"
	.globl _mtvec
_mtvec:
	.rept 32
	j _irq_dispatch
	.endr

	.section ".text.hot","ax"
	.globl __start
__start:
	/* Interrupts start disabled in both the user and machine contexts. */
	csrw mie,zero
	csrw myriscv.cie,zero
	la t0,.Luser_start
	csrw mepc,t0
	mret

.Luser_start:
	/* A pending level IRQ must not be delivered while either enable is clear. */
	li t0,IRQ_TIMER(IRQ_LEVEL)
	li t1,(512 << 16) | 32
	sw t1,0(t0)
	delay 128
	csrr t0,mip
	andi t0,t0,IRQ_BIT(IRQ_LEVEL)
	li t1,IRQ_BIT(IRQ_LEVEL)
	bne t0,t1,.Lfail
	la t0,irq_level_count
	lw t1,0(t0)
	bnez t1,.Lfail

	li t0,IRQ_BIT(IRQ_LEVEL)
	csrw mie,t0
	delay 64
	la t0,irq_level_count
	lw t1,0(t0)
	bnez t1,.Lfail

	/* Enable the current user context to deliver the pending IRQ. */
	li t0,2
	csrw myriscv.cie,t0
.Llevel_returned:
	delay 64
	la t0,irq_level_count
	lw t1,0(t0)
	li t2,1
	bne t1,t2,.Lfail
	delay 512
	csrr t0,mip
	andi t0,t0,IRQ_BIT(IRQ_LEVEL)
	bnez t0,.Lfail

	/*
	 * WFI must ignore events selected in rs1, wake for an unblocked event,
	 * and return all events pending when it completes.
	 */
	li t0,IRQ_TIMER(IRQ_WFI_MASKED)
	li t1,(512 << 16) | 32
	sw t1,0(t0)
	li t0,IRQ_TIMER(IRQ_WFI_WAKE)
	li t1,(512 << 16) | 160
	sw t1,0(t0)
	li t1,IRQ_BIT(IRQ_WFI_MASKED)
	wfi a0,t1
	andi t0,a0,IRQ_BIT(IRQ_WFI_MASKED) | IRQ_BIT(IRQ_WFI_WAKE)
	li t1,IRQ_BIT(IRQ_WFI_MASKED) | IRQ_BIT(IRQ_WFI_WAKE)
	bne t0,t1,.Lfail
	delay 512
	csrr t0,mip
	andi t0,t0,IRQ_BIT(IRQ_WFI_MASKED) | IRQ_BIT(IRQ_WFI_WAKE)
	bnez t0,.Lfail

	/*
	 * An edge IRQ remains pending after its input is deasserted, then is
	 * cleared when accepting the interrupt.
	 */
	li t0,IRQ_EDGE_MASK
	li t1,IRQ_BIT(IRQ_EDGE)
	sw t1,0(t0)
	li t0,IRQ_TIMER(IRQ_EDGE)
	li t1,(128 << 16) | 32
	sw t1,0(t0)
	wfi a0,zero
	andi t0,a0,IRQ_BIT(IRQ_EDGE)
	li t1,IRQ_BIT(IRQ_EDGE)
	bne t0,t1,.Lfail
	delay 256
	csrr t0,mip
	andi t0,t0,IRQ_BIT(IRQ_EDGE)
	li t1,IRQ_BIT(IRQ_EDGE)
	bne t0,t1,.Lfail

	li t0,IRQ_BIT(IRQ_EDGE)
	csrw mie,t0
.Ledge_returned:
	delay 64
	la t0,irq_edge_count
	lw t1,0(t0)
	li t2,1
	bne t1,t2,.Lfail
	csrr t0,mip
	andi t0,t0,IRQ_BIT(IRQ_EDGE)
	bnez t0,.Lfail

	finish TEST_PASS

.Lfail:
	finish TEST_FAIL

	/*
	 * MTVEC reset has vectoring disabled, so all interrupts first enter
	 * vector 0. Dispatch the interrupt lines this test uses explicitly.
	 */
_irq_dispatch:
	delay 16
	csrr t0,mcause
	li t1,MCAUSE_IRQ | IRQ_LEVEL
	beq t0,t1,_irq_1
	li t1,MCAUSE_IRQ | IRQ_EDGE
	beq t0,t1,_irq_3
	j .Lfail

	.globl _irq_1
_irq_1:
	csrr t0,mcause
	li t1,MCAUSE_IRQ | IRQ_LEVEL
	bne t0,t1,.Lfail
	la t0,irq_level_count
	lw t1,0(t0)
	addi t1,t1,1
	sw t1,0(t0)
	li t0,IRQ_BIT(IRQ_LEVEL)
	csrrc zero,mie,t0
	la t0,.Llevel_returned
	csrw mepc,t0
	mret

	.globl _irq_3
_irq_3:
	csrr t0,mcause
	li t1,MCAUSE_IRQ | IRQ_EDGE
	bne t0,t1,.Lfail
	la t0,irq_edge_count
	lw t1,0(t0)
	addi t1,t1,1
	sw t1,0(t0)
	li t0,IRQ_BIT(IRQ_EDGE)
	csrrc zero,mie,t0
	la t0,.Ledge_returned
	csrw mepc,t0
	mret

	.section ".sdata","aw"
	.balign 4
irq_level_count:
	.word 0
irq_edge_count:
	.word 0
