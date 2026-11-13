#include "test.h"

	/* "hot" for testing purposes... */
begin_func ___start hot
	.balign 4
	la a0,__BSS_START__
	la a2,__BSS_END__
	sub a2, a2, a0
	li a1, 0
	call memset
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
