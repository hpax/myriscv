#include "asm.h"

	.section ".text.hot.stop","ax"
	.balign 4
	.globl stop
stop:
	li a0,-1
1:
	sw a0,%lo(STOP)(zero)
	j 1b
