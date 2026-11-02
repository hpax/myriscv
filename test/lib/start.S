#include "test.h"

	/* "hot" for testing purposes... */
begin_func ___start hot
	.balign 4
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
	tail exit
	end ___start

	weakalias ___start, _start, __start

begin_func __Exit hot
	bnez a0, .L_fail
	finish TEST_PASS
.L_fail:
	finish TEST_FAIL
end __Exit

	weakalias __Exit, exit, _exit, _Exit
