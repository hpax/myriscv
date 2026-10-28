	.globl TTY
TTY = -1
	.globl STOP
STOP = -8
	.global TTYCHR
TTYCHR = -512

	.section ".null","a"
	.balign 4
	.globl _NULL
_NULL:
	.word 0

	.section ".init.reset","ax"
	.globl _reset
_reset:
	la sp, ___stack_top
	la gp, __global_pointer$
	la tp, __tdata_start
	j __start
