#include "ctest.h"

void puts(const char *p)
{
    if (likely(p)) {
	while (*p)
	    TTY = *p++;
    }
}

void printu32(const char *prefix, uint32_t v)
{
    char numbuf[12];
    puts(prefix);
    utoa32_dds(numbuf, v);
    puts(numbuf);
}

void printu64(const char *prefix, uint64_t w)
{
    char numbuf[24];
    puts(prefix);
    utoa64_dds(numbuf, w);
    puts(numbuf);
}

static void _printxn(uint32_t v, int n)
{
    static const char hexdigits[] = "0123456789abcdef";

    n <<= 2;
    do {
	n -= 4;
	unsigned int d = (v >> n) & 15;
	putc(hexdigits[d]);
    } while (n);
}

void printx32(const char *prefix, uint32_t v)
{
    puts(prefix);
    _printxn(v, 8);
}

void printx64(const char *prefix, uint64_t w)
{
    puts(prefix);
    _printxn(w >> 32, 8);
    _printxn(w, 8);
}
