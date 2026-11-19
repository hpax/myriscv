#include "test.h"

	.section ".text.hot.print_str","ax"
	.globl _print_str
	.balign 4
___print_str:
1:
	putcr	t0
	.balign	4
_print_str:
	lbu	t0, (a0)
	add	a0, a0, 1
	bnez	t0, 1b
	ret

	.section ".text.hot.print_hex","ax"
	.globl _print_hex
	.balign 4
_print_hex:
	add	sp, sp, -16
	sw	a1,   (sp)
	sw	a2,  4(sp)
	sw	a3,  8(sp)

	li	a1, 28
	la	a3, hexdigits

	.balign	4
1:
	extru	a2, a0, a1, 4
	lxsb	a2, (a3), a2
	add	a1, a1, -4
	putcr	a2
	bgez	a1, 1b

	lw	a1,   (sp)
	lw	a2,  4(sp)
	lw	a3,  8(sp)
	add	sp, sp, 16

	ret

	.section ".rodata.hot.print_hex","a"
	.balign	4
hexdigits:
	.ascii "0123456789abcdef"

	.section ".text.hot.print_dec","ax"
	.globl _print_dec
	.balign 4
_print_dec:
#ifdef WITH_Xpabdds
	// Convert to and print decimal using the dds instruction.
	// This is optimized for code size, not performance.
	beqz	a0, 4f

	add	sp, sp, -32
	sw	a1, 12(sp)
	sw	a2, 16(sp)
	sw	a3, 20(sp)
	sw	a4, 24(sp)
	// sw	a5, 28(sp)

	li	a4, 32
	clz	a1, a0
	and	a1, a1, ~3
	sll	a0, a0, a1
	sub	a4, a4, a1

	li	a1, 0x30000000		// Always at least one digit
	li	a2, 0
	li	a3, 0

	.balign	4
1:
	dds.d	a3, a3, a2
	dds.d	a2, a2, a1
	dds.b	a1, a1, a0, 0
	dds.d	a3, a3, a2
	dds.d	a2, a2, a1
	dds.b	a1, a1, a0, 1
	dds.d	a3, a3, a2
	dds.d	a2, a2, a1
	dds.b	a1, a1, a0, 2
	dds.d	a3, a3, a2
	dds.d	a2, a2, a1
	dds.b	a1, a1, a0, 3
	sll	a0, a0, 4
	add	a4, a4, -4
	bnez	a4, 1b

	sw	a3,     (sp)
	sw	a2,    4(sp)
	sw	a1,    8(sp)

	// Skip leading zeroes
	ctz	a4, a3
	ctz	a0, a2
	czero.nez a0, a0, a3
	add	a4, a4, a0
	ctz	a0, a1
	czero.nez a0, a0, a3
	czero.nez a0, a0, a2
	add	a4, a4, a0
	srl	a4, a4, 3	// Convert bits to bytes

	li	a1, 12		// Total length of buffer

	.balign	4
2:
	lxsb	a0, (sp), a4
	add	a4, a4, 1
	putcr	a0
	blt	a4, a1, 2b

	lw	a1, 12(sp)
	lw	a2, 16(sp)
	lw	a3, 20(sp)
	lw	a4, 24(sp)
	// lw	a5, 28(sp)
	add	sp, sp, 32

	ret
4:
	putc	'0'
	ret

#else
	// Convert to and print decimal without division using a table.
	add sp,sp,-32
	sw a1,(sp)
	sw a2,4(sp)
	sw a3,8(sp)
	sw a4,12(sp)
	sw a5,16(sp)

	la a2,decimal_table+4
	/* Handle the top digit specially to avoid overflow */
	lw a4,-4(a2)
	addi a3,a2,32			/* End of non-unit digit table */

	bltu a0,a4,.L_skip_leading

	li a1,4			/* Current bit value */
	sll a4,a4,2
	j .L_do_digit

	.balign 4
.L_next_digit:
	lw a4,(a2)
	add a2,a2,4
.L_do_normal_digit:
	li a1,8
	sll a4,a4,3

.L_do_digit:
	li a5,0x30
.L_bit_loop:
	bltu a0,a4,.L_lower
	add a5,a5,a1
	sub a0,a0,a4
.L_lower:
	srl a1,a1,1
	srl a4,a4,1
	bnez a1,.L_bit_loop
	putcr a5
	bne a2,a3,.L_next_digit

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

	.balign 4
.L_skip_leading:
	lw a4,(a2)
	add a2,a2,4
	bgeu a0,a4,.L_do_normal_digit
	bne a2,a3,.L_skip_leading
	j .L_unit

	.section ".rodata.hot.print_dec","a"
	.balign 4
decimal_table:
	.long  1000000000
	.long   100000000
	.long    10000000
	.long     1000000

	.long      100000
	.long       10000
	.long        1000
	.long	      100
	.long	       10

.L_dt_size = . - decimal_table
#endif
