#ifndef _TESTSYS_H
#define _TESTSYS_H 1

extern volatile char TTY;
extern volatile unsigned int STOP;

static inline void tty_putc(char c)
{
    TTY = c;
}

static inline void tty_puts(const char *s)
{
    while (*s)
	TTY = *s++;
}

static inline void stop(void)
{
    STOP = 0;
    __builtin_unreachable();
}

#endif
