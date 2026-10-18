#include "test.h"

	.section ".text.hot.stop","ax"
	.balign 4
	.globl stop
stop:
	li a0,TEST_STOP
	j break

	.section ".text.hot.pass","ax"
	.balign 4
	.globl pass
pass:
	li a0,TEST_PASS
	j break

	.section ".text.hot.fail","ax"
	.balign 4
	.globl fail
fail:
	li a0,TEST_FAIL
	j break

	.section ".text.hot.break","ax"
	.balign 4
	.globl break
break:
	mv s10,a0
	print "Tests done, running EBREAK.\n"
	mv a0,s10
	ebreak
	print "ERROR: fall through after EBREAK\n"
	finish TEST_FAIL
