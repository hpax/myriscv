#include "test.h"

	.section ".text.hot.__start","ax"
	.balign 4
	.weak __start
__start:
	la a0,__BSS_START__
	la a1,__BSS_END__
1:
	sw zero,(a0)
	sw zero,4(a0)
	sw zero,8(a0)
	sw zero,12(a0)
	sw zero,16(a0)
	sw zero,20(a0)
	sw zero,24(a0)
	sw zero,28(a0)
	bne a0,a1,1b

	call main
1:
	sw a0,%lo(STOP)(zero)
	j 1b
