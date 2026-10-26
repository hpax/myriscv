#include "test.h"

icache_size = 4096

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
	li a0,':'
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
	li a0,':'
	sb a0,%lo(TTY)(zero)
	mv a0,s1
	jal _print_hex
	crlf

	.option rvc

	/* Multiply me harder? */
	/* Test with forwarding */
mult_test:
	la a0,mult_str
	jal _print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulhu a0,a4,a5
	mul s0,a4,a5
	jal _print_hex
	mv a0,s0
	jal _print_hex
	crlf

	/* Test without forwarding */
	la a0,mult_str
	jal _print_str
	li s0,0x8dbbc2c2
	li s1,0xc6fc68b9
	mulhu a0,s0,s1
	jal _print_hex
	mul a0,s0,s1
	jal _print_hex
	crlf

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
	crlf

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
	crlf

	/* Funny instructions */
	add.xu sp,sp,16
	sh2sub a0,a1,a2
	baeqz a0,a1,1f
	nop
1:
	extru  a0,a1,16,2
	extrui a0,a1,16,2
	extru  a0,a1,a2,2

	extrs  a0,a1,16,2
	extrsi a0,a1,16,2
	extrs  a0,a1,a2,2

	extro  a0,a1,16,2
	extroi a0,a1,16,2
	extro  a0,a1,a2,2

	extrcs  a0,a1,16,2
	extrcsi a0,a1,16,2
	extrcs  a0,a1,a2,2

	zext   a3,a3,a4
	zext   a3,a3,0
	zext   a3,a3,1
	zext   a3,a3,2
	zext   a3,a3,3
	zext   a3,a3,4
	zext   a3,a3,5
	zext   a3,a3,6
	zext   a3,a3,7
	zext   a3,a3,8
	zext   a3,a3,9
	zext   a3,a3,10
	zext   a3,a3,11
	zext   a3,a3,12
	zext   a3,a3,13
	zext   a3,a3,14
	zext   a3,a3,15
	zext   a3,a3,16
	zext   a3,a3,17
	zext   a3,a3,18
	zext   a3,a3,19
	zext   a3,a3,20
	zext   a3,a3,21
	zext   a3,a3,22
	zext   a3,a3,23
	zext   a3,a3,24
	zext   a3,a3,25
	zext   a3,a3,26
	zext   a3,a3,27
	zext   a3,a3,28
	zext   a3,a3,29
	zext   a3,a3,30
	zext   a3,a3,31

	sext   a3,a3,a4
	sext   a3,a3,0
	sext   a3,a3,1
	sext   a3,a3,2
	sext   a3,a3,3
	sext   a3,a3,4
	sext   a3,a3,5
	sext   a3,a3,6
	sext   a3,a3,7
	sext   a3,a3,8
	sext   a3,a3,9
	sext   a3,a3,10
	sext   a3,a3,11
	sext   a3,a3,12
	sext   a3,a3,13
	sext   a3,a3,14
	sext   a3,a3,15
	sext   a3,a3,16
	sext   a3,a3,17
	sext   a3,a3,18
	sext   a3,a3,19
	sext   a3,a3,20
	sext   a3,a3,21
	sext   a3,a3,22
	sext   a3,a3,23
	sext   a3,a3,24
	sext   a3,a3,25
	sext   a3,a3,26
	sext   a3,a3,27
	sext   a3,a3,28
	sext   a3,a3,29
	sext   a3,a3,30
	sext   a3,a3,31

	oext   a3,a3,a4
	oext   a3,a3,0
	oext   a3,a3,1
	oext   a3,a3,2
	oext   a3,a3,3
	oext   a3,a3,4
	oext   a3,a3,5
	oext   a3,a3,6
	oext   a3,a3,7
	oext   a3,a3,8
	oext   a3,a3,9
	oext   a3,a3,10
	oext   a3,a3,11
	oext   a3,a3,12
	oext   a3,a3,13
	oext   a3,a3,14
	oext   a3,a3,15
	oext   a3,a3,16
	oext   a3,a3,17
	oext   a3,a3,18
	oext   a3,a3,19
	oext   a3,a3,20
	oext   a3,a3,21
	oext   a3,a3,22
	oext   a3,a3,23
	oext   a3,a3,24
	oext   a3,a3,25
	oext   a3,a3,26
	oext   a3,a3,27
	oext   a3,a3,28
	oext   a3,a3,29
	oext   a3,a3,30
	oext   a3,a3,31

	ecall

	/* Test writing to and running from external memory */
extmem_test:
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
	crlf

	/* What does fence.i actually do */
	fence.i
	lw a0,3(zero)	/* Make the M stage busy */
	fence.i

	/* icache test: put a bunch of "add a0,a0,1" instructions in external
	 * memory, then run several times and compare the time.
	 * Writing to address -16 generates a time stamp on the
	 * simulation console.
	*/
icache_test:
	la s9,itest_insns
	lw a0,(s9)		// addi a0,a0,1
	lw s3,4(s9)		// ret
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
	lw a0,8(s9)		// addi a0,a0,2
	li s8,icache_size	// Conflicting offset - modify as needed

	add s2,s8,s0
	mv a1,s2
	add a2,s2,256*4
1:
	sw a0,(a1)
	add a1,a1,4
	bne a1,a2,1b

	sw s3,(a1)		// ret

	fence.i

	/* Initial speed test */
icache1:
	print "Icache speed test (should increment by 0x100):\n"
	li s1,5			// Loop count
	li a0,0
	sw a0,-16(zero)
2:
	add s1,s1,-1
	jalr (s0)
	sw a0,-16(zero)
	bnez s1,2b

	/* Cache one-conflict test */
icache2:
	print "Icache single conflict test (should increment by 0x200):\n"
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
icache3:
	print "Icache overwrite test (should increment by 0x400):\n"
	lw a0,12(s9)		// addi a0,a0,4
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

	/* Icache test where every instruction is a tag conflict */
icache4:
	print "Icache chronic conflict test (should increment by 0x800):\n"
	lw a0,16(s9)		// addi a0,a0,8
	lw t1,20(s9)		// Jump one icache length

	sll a2,s8,8		// s8 = icache_size
	mv a1,s2
	add a2,s2,a2
1:
	sw a0,(a1)
	sw t1,4(a1)
	add a1,a1,s8
	bne a1,a2,1b

	sw s3,(a1)		// ret

	fence.i

	li s1,5			// Loop count
	li a0,0
	sw a0,-16(zero)
2:
	add s1,s1,-1
	jalr (s2)
	sw a0,-16(zero)
	bnez s1,2b

done:
	/* Done with tests */
	la a0,done_str
	jal _print_str
	ebreak
	la a0,ebreak_failed_str
	jal _print_str
	j stop

	ret

	.balign 4
	.option push
	.option norvc
	.option norelax
itest_insns:
	addi a0,a0,1
	ret
	addi a0,a0,2
	addi a0,a0,4
1:	addi a0,a0,8
	j 1b+icache_size
	.option pop

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
