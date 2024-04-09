#include "asm.h"

	.section ".text.hot","ax"
	.globl __start
__start:

	/* Test with instruction in the load hazard slot */
test1:
	la a0,hello1_str
	lbu a1,(a0)
	add a0,a0,1
	beqz a1,2f
1:
	sb a1,%lo(TTY)(zero)
	lbu a1,(a0)
	add a0,a0,1
	bnez a1,1b

2:

	/* The same, but misaligned */
test1a:
	.balign 4
	c.nop
	la a0,hello2_str
	lbu a1,(a0)
	add a0,a0,1
	beqz a1,2f
1:
	sb a1,%lo(TTY)(zero)
	lbu a1,(a0)
	add a0,a0,1
	bnez a1,1b

2:

	/* Test with load to branch hazard */
test2:
	la a0,hello3_str
	lbu a1,(a0)
	beqz a1,2f
1:
	add a0,a0,1
	sb a1,%lo(TTY)(zero)
	lbu a1,(a0)
	bnez a1,1b

	/* Unaligned memory test */
	.option norvc
	.balign 4
unalign_test:
	la a0,unaligned_str
	jal _print_str
	la s0,udata_buf
	lw a0,2(s0)
	jal _print_hex

	/* Write test variant 1 */
	la a0,unaligned_str2
	jal _print_str
	li a1,0xddccbbaa
	sw a1,1(s0)
	lw a0,4(s0)
	jal _print_hex
	li a0,':
	sb a0,%lo(TTY)(zero)
	lw a0,(s0)
	jal _print_hex

	/* Write test variant 2 */
	la a0,unaligned_str2
	jal _print_str
	li a1,0xddccbbaa
	sw a1,1(s0)
	lw s1,(s0)
	lw a0,4(s0)
	jal _print_hex
	li a0,':
	sb a0,%lo(TTY)(zero)
	mv a0,s1
	jal _print_hex
	print_crlf

	.option rvc

	/* Multiply me harder? */
	/* Test with forwarding */
	la a0,mult_str
	jal _print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulhu a0,a4,a5
	mul s0,a4,a5
	jal _print_hex
	mv a0,s0
	jal _print_hex
	print_crlf

	/* Test without forwarding */
	la a0,mult_str
	jal _print_str
	li s0,0x8dbbc2c2
	li s1,0xc6fc68b9
	mulhu a0,s0,s1
	jal _print_hex
	mul a0,s0,s1
	jal _print_hex
	print_crlf

	/* Signed multiply test */
	la a0,mults_str
	jal _print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulh a0,a4,a5
	mul s0,a4,a5
	jal _print_hex
	mv a0,s0
	jal _print_hex
	print_crlf

	/* Mixed multiply test */
	la a0,multsu_str
	jal _print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulhsu a0,a4,a5
	mul s0,a4,a5
	jal _print_hex
	mv a0,s0
	jal _print_hex
	print_crlf

	/* Test writing to and running from external memory */
	la a0,extmem1_str
	jal _print_str
	li a0,0x80824531		// li a0,12; ret
	la s0,0x40000000
	sw a0,(s0)
	fence.i
	li a0,0
	jalr (s0)			// Should be uncached
	jalr (s0)			// Should be cached
	jalr (s0)			// Should be cached w/o overrun?
	call _print_hex
	print_crlf

	/* What does fence.i actually do */
	fence.i
	lw a0,3(zero)	/* Make the M stage busy */
	fence.i

	/* icache test: put a bunch of "add a0,a0,1" instructions in external
	 * memory, then run several times and compare the time.
	 * Writing to address -16 generates a time stamp on the
	 * simulation console.
	 */
	li a0,0x00150513	// addi a0,a0,1
	li s3,0x00008067	// ret
	mv a1,s0
	add a2,a1,256*4
1:
	sw a0,(a1)
	add a1,a1,4
	bne a1,a2,1b

	sw s3,(a1)		// ret

	/*
	 * This set of instructions are add a0,a0,2; the addresses are
	 * intended to conflict to test eviction on tag mismatch.
	 */
	li a0,0x00250513	// addi a0,a0,2
	li a1,4096		// Conflicting offset - modify as needed

	add s2,a1,s0
	mv a1,s2
	add a2,s2,256*4
1:
	sw a0,(a1)
	add a1,a1,4
	bne a1,a2,1b

	sw s3,(a1)		// ret

	fence.i

	/* Initial speed test */
	print "Icache speed test (increment by 0x100):\n"

	li s1,5			// Loop count
	li a0,0
	sw a0,-16(zero)
2:
	add s1,s1,-1
	jalr (s0)
	sw a0,-16(zero)
	bnez s1,2b

	/* Cache conflict test */
	print "Icache conflict test (increment by 0x200):\n"

	li s1,5			// Loop count
	li a0,0
	sw a0,-16(zero)
2:
	add s1,s1,-1
	jalr (s2)
	sw a0,-16(zero)
	bnez s1,2b

	/* Cache overwrite test */
	/* Overwriting existing code, should cause icache invalidation */

	print "Icache overwrite test (increment by 0x400):\n"

	li a0,0x00450513	// addi a0,a0,4
	mv a1,s2
	add a2,a1,256*4
1:
	sw a0,(a1)
	add a1,a1,4
	bne a1,a2,1b

	// ret should already be there, so this tests that, too...

	fence.i

	li s1,5			// Loop count
	li a0,0
	sw a0,-16(zero)
2:
	add s1,s1,-1
	jalr (s2)
	sw a0,-16(zero)
	bnez s1,2b

	/* Done with tests */
	la a0,done_str
	jal _print_str
	ebreak
	la a0,ebreak_failed_str
	jal _print_str
	j stop

	ret

	.section ".rodata.hot","a"
hello1_str:
	.asciz "Hello, World #1!\n"
hello2_str:
	.asciz "Hello, World #2!\n"
hello3_str:
	.asciz "Hello, World #3!\n"
unaligned_str:
	.asciz "Unaligned read test:  "
unaligned_str2:
	.asciz "\nUnaligned write test: "
mult_str:
	.asciz "UU Multiply test, expect 6e2af77076c68e32: "
mults_str:
	.asciz "SS Multiply test, expect 1972cbf576c68e32: "
multsu_str:
	.asciz "SU Multiply test, expect a72e8eb776c68e32: "
extmem1_str:
	.asciz "External memory test: "
done_str:
	.asciz "Tests done, running EBREAK.\n"
ebreak_failed_str:
	.asciz "ERROR: fall through after ebreak\n"

	.section ".sdata","aw"
	.balign 4
udata_buf:
	.word	0x33221100
	.word	0x77665544
