/*
 * myriscv.h
 *
 * MyRISCV-specific operations
 */

#ifndef _MYRISCV_H
#define _MYRISCV_H

#include <stddef.h>
#include <stdbool.h>

#ifndef __riscv_xpaimy
#define ___use_xpaimy(__a, __b, __c) 0
#else
#define ___use_xpaimy(__a, __b, __c)		\
    (!__builtin_constant_p(__a) ||		\
     !__builtin_constant_p(__b) ||		\
     !__builtin_constant_p(__c))
#endif

static inline __attribute__((__const__))
unsigned int ___myriscv_dds_const(unsigned int __p, bool __i)
{
    unsigned int __a, __b, __c, __d;

    __a = (__p >> 24) & 0xf; __a += (__a >= 5);
    __b = (__p >> 16) & 0xf; __b += (__b >= 5);
    __c = (__p >>  8) & 0xf; __c += (__c >= 5);
    __d = __p & 0xf;         __d += (__d >= 5);

    __a = (__a << 1) + __i;
    __b = (__b << 1) + (__a >> 4);
    __c = (__c << 1) + (__b >> 4);
    __d = (__d << 1) + (__c >> 4);

    __a = (__a & 15) ? __a | 0x30 : 0;
    __b = (__b & 15) ? __b | 0x30 : 0;
    __c = (__c & 15) ? __c | 0x30 : 0;
    __d = (__d & 15) ? __d | 0x30 : 0;

    __p &= 0x20202020;
    __p |= __a << 24;
    __p |= __b << 16;
    __p |= __c <<  8;
    __p |= __d;

    return __p;
}

static inline __attribute__((__const__))
unsigned int __myriscv_dds_b(unsigned int __p, unsigned int __i,
			     unsigned int __s)
{
    if (___use_xpaimy(__p, __i, 0)) {
	unsigned int __v;
	if (!__builtin_constant_p(__s) || __s > 3U) {
	    __i >>= __s;
	    __s = 0;
	}
	asm("dds.b %0, %z1, %z2, %3"
	    : "=r" (__v) : "Jr" (__p), "Jr" (__i), "i" (__s));
	return __v;
    } else {
	return ___myriscv_dds_const(__p, __i >> (31U - __s));
    }
}

static inline __attribute__((__const__))
unsigned int __myriscv_dds_d(unsigned int __p, unsigned int __i)
{
    if (___use_xpaimy(__p, __i, 0)) {
	unsigned int __v;
	asm("dds.d %0, %z1, %z2" : "=r" (__v) : "Jr" (__p), "Jr" (__i));
	return __v;
    } else {
	return ___myriscv_dds_const(__p, (__i & 15) >= 5U);
    }
}

static inline __attribute__((__const__)) unsigned int
__myriscv_extru(unsigned int __v, unsigned int __s, unsigned int __w)
{
    if (___use_xpaimy(__v, __s, 0) && __builtin_constant_p(__w)) {
	asm("extru %0, %1, %2, %3"
	    : "=r" (__v)
	    : "Jr" (__v), "Jr" (__s), "i" (__w));
    } else {
	__v >>= __s;
	__w = 32 - __w;
	__v = __v << __w >> __w;
    }
    return __v;
}
static inline __attribute__((__const__)) int
__myriscv_extrs(int __v, unsigned int __s, unsigned int __w)
{
    if (___use_xpaimy(__v, __s, 0) && __builtin_constant_p(__w)) {
	asm("extrs %0, %1, %2, %3"
	    : "=r" (__v)
	    : "Jr" (__v), "Jr" (__s), "i" (__w));
    } else {
	__v >>= __s;
	__w = 32 - __w;
	__v = __v << __w >> __w;
    }
    return __v;
}

#endif /* _MYRISCV_H */
