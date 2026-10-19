#ifndef _TEST_H
#define _TEST_H 1

#include "riscv.h"
#include "../../rtl/params.h"

/*
 * Test output status codes - all constants directly correspond to the
 * four-letter ASCII string in the name (space-padded if necessary)
 */
#define TEST_PASS	0x53534150
#define TEST_FAIL	0x4c494146
#define TEST_STOP	0x504f5453
#define TEST_VOID	0x44494f56
#define TEST_TRAP	0x50415254

#ifdef __ASSEMBLER__

#include "testasm.h"

#else

extern volatile char		TTY;
extern volatile char		TTYCHR[256];
extern volatile unsigned int	STOP;

static inline void tty_putc(unsigned char c)
{
    if (__builtin_constant_p(c))
	TTYCHR[c] = 0;
    else
	TTY = c;
}

static inline void tty_puts(const char *s)
{
    while (*s)
	TTY = *s++;
}

static inline __attribute__((noreturn)) void stop(unsigned int status)
{
    while (1)
	STOP = status;
    __builtin_unreachable();
}


__attribute__((noreturn)) void
__assert_fail(const void *what, const void *file,
	      const void *func, unsigned long line);

#define assert(x)					     \
    do {						     \
	if (!__builtin_expect(!!(x),1))			     \
	    __assert_fail(#x, __FILE__, __func__, __LINE__); \
    } while (0)

#endif

#endif
