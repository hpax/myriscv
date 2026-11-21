#include "test.h"

void printu32(const char *prefix, uint32_t v);
void printu64(const char *prefix, uint64_t v);
void printx32(const char *prefix, uint32_t v);
void printx64(const char *prefix, uint64_t v);
void puts(const char *);
#define putc    tty_putc
#define putchar tty_putc
