#include "test.h"

#define TTY  (*(volatile char *)(-1))
#define STOP (*(volatile unsigned int *)(-16))

extern char *utoa32_dds(char *buf, uint32_t val);
extern char *utoa64_dds(char *buf, uint64_t val);

int main(void)
{
    char numbuf[32];

    tty_puts("Hello, C world!\n");

    for (int i = 1; i <= 5; i++) {
	uint32_t x = i;
	uint32_t v = x;
	for (int j = 0; j <= 10; j++) {
	    utoa32_dds(numbuf, v);
	    tty_puts(numbuf);
	    tty_putc('\n');
	    x *= 10;
	    v += x;
	}
    }

    for (int i = 1; i <= 5; i++) {
	uint64_t y = i;
	uint64_t w = y;
	for (int j = 0; j <= 20; j++) {
	    utoa64_dds(numbuf, w);
	    tty_puts(numbuf);
	    tty_putc('\n');
	    y *= 10;
	    w += y;
	}
    }

    uint32_t insns, cycles;
    asm volatile("csrr %0,cycle; csrr %1,instret"
		 : "=r" (cycles), "=r" (insns));

    tty_puts("Instructions: ");
    utoa32_dds(numbuf, insns);
    tty_puts(numbuf);
    tty_puts("  Cycles: ");
    utoa32_dds(numbuf, cycles);
    tty_puts(numbuf);
    tty_putc('\n');

    return 0;
}
