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
