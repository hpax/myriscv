#include "ctest.h"

#define TTY  (*(volatile char *)(-1))
#define STOP (*(volatile unsigned int *)(-16))

extern char *utoa32_dds(char *buf, uint32_t val);
extern char *utoa64_dds(char *buf, uint64_t val);

int main(void)
{
    puts("Hello, C world!\n");

    for (int i = 1; i <= 5; i++) {
	uint32_t x = i;
	uint32_t v = x;
	for (int j = 0; j <= 10; j++) {
	    printu32(NULL, v);
	    putc('\n');
	    x *= 10;
	    v += x;
	}
    }

    for (int i = 1; i <= 5; i++) {
	uint64_t y = i;
	uint64_t w = y;
	for (int j = 0; j <= 20; j++) {
	    printu64(NULL, w);
	    putc('\n');
	    y *= 10;
	    w += y;
	}
    }

    uint32_t insns, cycles;
    asm volatile("csrr %0,cycle; csrr %1,instret"
		 : "=r" (cycles), "=r" (insns));

    printu32("Instructions: ", insns);
    printu32("  Cycles: ", cycles);
    putc('\n');

    return 0;
}
