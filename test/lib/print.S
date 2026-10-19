#include "test.h"

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
#if 1
	bgeu a2,a4,2f
	add a2,a2,a5
2:
#else
	sltu a3,a2,a4
	czero.eqz a3,a5,a3
	add a2,a2,a3
#endif
	putcr a2
	add a1,a1,-1
	bnez a1,1b

	lw a1,(sp)
	lw a2,4(sp)
	lw a3,8(sp)
	lw a4,12(sp)
	lw a5,16(sp)
	add sp,sp,32

	ret

	// Convert to and print decimal without division using a table.
	.section ".text.hot.print_dec","ax"
	.globl _print_dec
	.balign 4
_print_dec:
	add sp,sp,-32
	sw a1,(sp)
	sw a2,4(sp)
	sw a3,8(sp)
	sw a4,12(sp)
	sw a5,16(sp)

	la a2,decimal_table+4
	add a3,a2,9*4-8		/* End of non-unit digit table */

	/* Handle the top digit specially to avoid overflow */
	lw a4,-4(a2)
	blt a0,a4,.L_skip_leading

	li a1,4			/* Current bit position */
	sll a4,a4,2
.L_digit_loop:
	li a5,0x30
.L_bit_loop:
	ble a0,a4,.L_lower
	add a5,a5,a1
	sub a0,a0,a4
.L_lower:
	srl a1,a1,1
	srl a4,a4,1
	bnez a1,.L_bit_loop
	putcr a5
	beq a2,a3,.L_unit

.L_next_digit:
	lw a4,(a2)
	add a2,a2,4
.L_do_digit:
	li a1,8
	sll a4,a4,3
	j .L_digit_loop

	.balign 4
.L_skip_leading:
	lw a4,(a2)
	add a2,a2,4
	bge a0,a4,.L_do_digit
	bne a2,a3,.L_skip_leading

.L_unit:
	add a0,a0,0x30
	putcr a0

	lw a1,(sp)
	lw a2,4(sp)
	lw a3,8(sp)
	lw a4,12(sp)
	lw a5,16(sp)
	add sp,sp,32

	ret

	.section ".rodata.hot.print_dec","a"
	.balign 4
decimal_table:
	.long 10000000000
	.long  1000000000
	.long   100000000
	.long    10000000
	.long     1000000
	.long      100000
	.long       10000
	.long        1000
	.long	      100
	.long	       10
