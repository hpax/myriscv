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

#include "asm.h"
#include "testasm.h"

#else

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#define noreturn	__attribute__((__noreturn__))
#define unreachable()	__builtin_unreachable()
#define likely(x)	__builtin_expect(!!(x), 1)
#define unlikely(x)	__builtin_expect(!!(x), 0)
#define __hot		__attribute__((__hot__))
#define __cold		__attribute__((__cold__))

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

static inline noreturn void stop(unsigned int status)
{
    while (1)
	STOP = status;
    __builtin_unreachable();
}

noreturn void __assert_fail(const void *what, const void *file,
			    const void *func, unsigned long line);

#define assert(x)					     \
    do {						     \
	if (!__builtin_expect(!!(x),1))			     \
	    __assert_fail(#x, __FILE__, __func__, __LINE__); \
    } while (0)

#endif

#endif
