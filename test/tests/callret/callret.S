#include "test.h"

icache_size = 4096

	.section ".text.hot","ax"
	.globl __start
__start:

	/* Call and return stack test */
	call print_stuff

done:
	/* Done with tests */
	j stop

print_stuff:
	mv s3,ra

	li s0,1
	li s1,16
	li s2,5
1:
	mv a0,s0
	call _print_hex
	crlf
	addi s1,s1,-1
	mul s0,s0,s2
	bnez s1,1b

	mv ra,s3
	ret
