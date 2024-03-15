	.option arch,rv32imc
	.option arch,+zba
	.option arch,+zbb
	.option arch,+zbs
	.option arch,+zicsr

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
	
	/* Test with load to branch hazard */
test1:
	la a0,hello1_str
	lbu a1,(a0)
	beqz a1,2f
1:
	add a0,a0,1
	sb a1,TTY(zero)
	lbu a1,(a0)
	bnez a1,1b

	/* Test with other instruction in the hazard slot */
test2:
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
	la a0,crlf_str
print_str:
	lbu a1,(a0)
	add a0,a0,1
	beqz a1,2f
1:
	sb a1,TTY(zero)
	lbu a1,(a0)
	add a0,a0,1
	bnez a1,1b
	ret

print_hex:
	li a1,8
	li a3,0x3a
1:
	ror a0,a0,32-4
	and a2,a0,15
	add a2,a2,0x30
	blt a2,a3,2f
	add a2,a2,0x61-0x30-10
2:	sb a2,TTY(zero)
	add a1,a1,-1
	bnez a1,1b
	ret
	
	.section ".rodata.hot","a"
hello1_str:
	.asciz "Hello, World #1!\r\n"
hello2_str:
	.asciz "Hello, World #1!\r\n"
ebreak_failed_str:
	.asciz "ERROR: fall through after ebreak\r\n"
irq_str:
	.asciz "Interrupt/exception triggered\r\nmepc   = "
mcause_str:
	.asciz "\r\nmcause = "
crlf_str:
	.asciz "\r\n"

	.section ".stack","a"
	.balign 16
	.globl ___stack
	.globl ___stack_top
___stack:
	.space 2048
___stack_top:
