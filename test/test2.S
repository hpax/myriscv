	.option arch,rv32imc
	.option arch,+zba
	.option arch,+zbb
	.option arch,+zbs
	.option arch,+zicond
	.option arch,+zicsr
	.option arch,+zifencei
	.option arch,+zmmul

	TTY  = -1
	STOP = -8

	.section ".null","a"
	.balign 4
	.globl ___NULL
___NULL:
	.word 0

	.section ".init.reset","ax"
	.balign 4
	.globl ___reset
___reset:
	.option push
	.option norelax
	la sp, ___stack_top
	la gp, __global_pointer$
	.option pop
	.option push
	j _start

	.section ".init.irq","ax"
	.globl ___mtvec
___mtvec:
	.rept 32
	.balign 4
	j _irq_common
	.endr

	.section ".text.hot","ax"
	.globl _start
_start:

	/* Test with instruction in the load hazard slot */
test1:
	la a0,hello1_str
	lbu a1,(a0)
	add a0,a0,1
	beqz a1,2f
1:
	sb a1,TTY(zero)
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
	sb a1,TTY(zero)
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
	sb a1,TTY(zero)
	lbu a1,(a0)
	bnez a1,1b

	/* Unaligned memory test */
unalign_test:
	la a0,unaligned_str
	jal print_str
	la s0,udata_buf
	lw a0,2(s0)
	jal print_hex

	/* Write test variant 1 */
	la a0,unaligned_str2
	jal print_str
	li a1,0xddccbbaa
	sw a1,1(s0)
	lw a0,4(s0)
	jal print_hex
	li a0,':
	sb a0,TTY(zero)
	lw a0,(s0)
	jal print_hex

	/* Write test variant 2 */
	la a0,unaligned_str2
	jal print_str
	li a1,0xddccbbaa
	sw a1,1(s0)
	lw s1,(s0)
	lw a0,4(s0)
	jal print_hex
	li a0,':
	sb a0,TTY(zero)
	mv a0,s1
	jal print_hex

	jal print_crlf

	/* Multiply me harder? */
	/* Test with forwarding */
	la a0,mult_str
	jal print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulhu a0,a4,a5
	mul s0,a4,a5
	jal print_hex
	mv a0,s0
	jal print_hex
	jal print_crlf

	/* Test without forwarding */
	la a0,mult_str
	jal print_str
	li s0,0x8dbbc2c2
	li s1,0xc6fc68b9
	mulhu a0,s0,s1
	jal print_hex
	mul a0,s0,s1
	jal print_hex
	jal print_crlf

	/* Signed multiply test */
	la a0,mults_str
	jal print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulh a0,a4,a5
	mul s0,a4,a5
	jal print_hex
	mv a0,s0
	jal print_hex
	jal print_crlf

	/* Mixed multiply test */
	la a0,multsu_str
	jal print_str
	li a4,0x8dbbc2c2
	li a5,0xc6fc68b9
	mulhsu a0,a4,a5
	mul s0,a4,a5
	jal print_hex
	mv a0,s0
	jal print_hex
	jal print_crlf

	/* Test writing to and running from external memory */
	la a0,extmem1_str
	jal print_str
	li a0,0x80824531		// li a0,12; ret
	la s0,0x40000000
	sw a0,(s0)
	fence.i
	li a0,0
	jalr (s0)			// Should be uncached
	jalr (s0)			// Should be cached
	jalr (s0)			// Should be cached w/o overrun?
	call print_hex
	call print_crlf

	/* What does fence.i actually do */
	fence.i
	lw a0,3(zero)	/* Make the M stage busy */
	fence.i

	/* icache test: put a bunch of "add a0,a0,1" instructions in external
	 * memory, then run twice and compare the speed.
	 * Writing to address -16 generates a time stamp on the
	 * simulation console.
	 */
	la a0,icache_str
	jal print_str

	li a0,0x00150513	// addi a0,a0,1
	mv a1,s0
	add a2,a1,256*4
1:
	sw a0,(a1)
	add a1,a1,4
	bne a1,a2,1b

	li a0,0x00008067	// ret
	sw a0,(a1)

	fence.i

	li s1,5			// Loop count
	li a0,0
	sw a0,-16(zero)
2:
	add s1,s1,-1
	jalr (s0)
	sw a0,-16(zero)
	bnez s1,2b

	/* Done */
	la a0,done_str
	jal print_str
	ebreak
	la a0,ebreak_failed_str
	jal print_str
	j kill_simulation

	.balign 4
_irq_common:
	la a0,irq_str
	jal print_str
	csrr a0,mepc
	jal print_hex
	la a0,mcause_str
	jal print_str
	csrr a0,mcause
	jal print_hex
	jal print_crlf
	nop
	nop
	nop
	nop
	nop
	nop
	.balign 4
kill_simulation:
	sb zero,STOP(zero)
	j kill_simulation

print_crlf:
	li a0,10
	sb a0,TTY(zero)
	ret

print_str:
	lbu a1,(a0)
	add a0,a0,1
	beqz a1,2f
1:
	sb a1,TTY(zero)
	lbu a1,(a0)
	add a0,a0,1
	bnez a1,1b
2:
	ret

print_hex:
	li a1,8
	li a4,0x61
	li a5,0x30-(0x61-10)
1:
	ror a0,a0,32-4
	and a2,a0,15
	add a2,a2,0x61-10
#if 0
	bgeu a2,a4,2f
	add a2,a2,a5
2:
#else
	sltu a3,a2,a4
	czero.eqz a3,a5,a3
	add a2,a2,a3
#endif
	sb a2,TTY(zero)
	add a1,a1,-1
	bnez a1,1b
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
icache_str:
	.asciz "Icache test, second time should be faster: "
done_str:
	.asciz "Tests done, running EBREAK.\n"
ebreak_failed_str:
	.asciz "ERROR: fall through after ebreak\n"
irq_str:
	.asciz "Interrupt/exception triggered!\nmepc   = "
mcause_str:
	.asciz ", mcause = "

	.section ".sdata","aw"
	.balign 4
udata_buf:
	.word	0x33221100
	.word	0x77665544

	.section ".stack","a"
	.balign 16
	.globl ___stack
	.globl ___stack_top
___stack:
	.space 2048
___stack_top:
