#include "test.h"

	.section ".init.irq","ax"
	.globl _mtvec
_mtvec:
	j _irq_0
	j _irq_1
	j _irq_2
	j _irq_3
	j _irq_4
	j _irq_5
	j _irq_6
	j _irq_7
	j _irq_8
	j _irq_9
	j _irq_10
	j _irq_11
	j _irq_12
	j _irq_13
	j _irq_14
	j _irq_15
	j _irq_16
	j _irq_17
	j _irq_18
	j _irq_19
	j _irq_20
	j _irq_21
	j _irq_22
	j _irq_23
	j _irq_24
	j _irq_25
	j _irq_26
	j _irq_27
	j _irq_28
	j _irq_29
	j _irq_30
	j _irq_31

	.section ".text.hot","ax"
	.globl _irq_common
	.balign 4
_irq_common:
	mv s11,a0
	print "Interrupt/exception triggered!\nmepc   = "
	csrr a0,mepc
	call _print_hex
	print ", mcause = "
	csrr a0,mcause

	/* If trap is not EBREAK, set exit cause to TRAP */
	li a1,MCAUSE_BREAK
	beq a0,a1,1f
	li s11,TEST_TRAP
1:

	call _print_hex
	crlf

2:
	sw s11,%lo(STOP)(zero)
	j 2b

	.weakref _irq_0, _irq_common
	.weakref _irq_1, _irq_common
	.weakref _irq_2, _irq_common
	.weakref _irq_3, _irq_common
	.weakref _irq_4, _irq_common
	.weakref _irq_5, _irq_common
	.weakref _irq_6, _irq_common
	.weakref _irq_7, _irq_common
	.weakref _irq_8, _irq_common
	.weakref _irq_9, _irq_common
	.weakref _irq_10, _irq_common
	.weakref _irq_11, _irq_common
	.weakref _irq_12, _irq_common
	.weakref _irq_13, _irq_common
	.weakref _irq_14, _irq_common
	.weakref _irq_15, _irq_common
	.weakref _irq_16, _irq_common
	.weakref _irq_17, _irq_common
	.weakref _irq_18, _irq_common
	.weakref _irq_19, _irq_common
	.weakref _irq_20, _irq_common
	.weakref _irq_21, _irq_common
	.weakref _irq_22, _irq_common
	.weakref _irq_23, _irq_common
	.weakref _irq_24, _irq_common
	.weakref _irq_25, _irq_common
	.weakref _irq_26, _irq_common
	.weakref _irq_27, _irq_common
	.weakref _irq_28, _irq_common
	.weakref _irq_29, _irq_common
	.weakref _irq_30, _irq_common
	.weakref _irq_31, _irq_common
