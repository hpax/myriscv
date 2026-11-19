/*
 * utoa.c
 *
 * Convert unsigned numbers to decimal.
 */

#include "test.h"

#ifndef UNROLL
#define UNROLL 1
#endif

/*
 * It is always safe to do a few extra iterations, and it cuts down
 * the code size when unrolled by over 20%.
 */
#if UNROLL
#define UNROLL_MASK 3
#define UNROLL_BITS 4
#else
#define UNROLL_MASK 0
#define UNROLL_BITS 1
#endif

/*
 * Convert val (0 <= val < 10^4) to 4 big-endian ASCII digits in a uint32_t,
 * NUL-padded in the least-significant bytes with at least one digit ('0'..'9').
 */
static uint32_t dds_chunk4_trim(uint32_t val)
{
    uint32_t d0 = 0x30000000u; /* "\0\0\00" (LSD in bits [31:24]) */

    if (likely(val)) {
        int lz = __builtin_clz(val) & ~UNROLL_MASK;
        uint32_t bits = val << lz;

        for (int i = lz; i < 32; i += UNROLL_BITS) {
	    d0 = __myriscv_dds_b(d0, bits, 0);
#if UNROLL
	    d0 = __myriscv_dds_b(d0, bits, 1);
	    d0 = __myriscv_dds_b(d0, bits, 2);
	    d0 = __myriscv_dds_b(d0, bits, 3);
#endif
	    bits <<= UNROLL_BITS;
        }
    }
    return d0;
}

/*
 * Write a NUL-padded 4-byte dds word (guaranteed non-zero) to dst,
 * stripping leading NULs. Returns pointer past the written digits.
 */
static char *store_trimmed4(char *dst, uint32_t w)
{
    unsigned skip = __builtin_ctz(w) & ~7; /* 0..3 leading NUL bytes */
    unsigned len  = 4 - (skip >> 3);       /* 1..4 ASCII digits */

    w >>= skip;
    *(uint32_t *)dst = w;
    return dst + len;
}

struct dword {
    uint32_t lo, hi;
};
static struct dword dds_chunk8(uint32_t val, struct dword w)
{
    if (likely(val)) {
	int lz = __builtin_clz(val) & ~UNROLL_MASK;
	uint32_t bits = val << lz;

	for (int i = lz; i < 32; i += UNROLL_BITS) {
	    w.hi = __myriscv_dds_d(w.hi, w.lo);
	    w.lo = __myriscv_dds_b(w.lo, bits, 0);
#if UNROLL
	    w.hi = __myriscv_dds_d(w.hi, w.lo);
	    w.lo = __myriscv_dds_b(w.lo, bits, 1);
	    w.hi = __myriscv_dds_d(w.hi, w.lo);
	    w.lo = __myriscv_dds_b(w.lo, bits, 2);
	    w.hi = __myriscv_dds_d(w.hi, w.lo);
	    w.lo = __myriscv_dds_b(w.lo, bits, 3);
#endif
	    bits <<= UNROLL_BITS;
	}
    }
    return w;
}

/*
 * Convert val (10^4 <= val < 10^8) to 8 big-endian ASCII digits across
 * (*hi_out, *lo_out). Because val >= 10^4, *hi_out is guaranteed non-zero
 * and all 4 bytes of *lo_out are guaranteed printable ('0'..'9').
 */
static __attribute((__always_inline__))
struct dword dds_chunk8_trim(uint32_t val)
{
    struct dword w = { .lo = 0x30000000, .hi = 0 };
    return dds_chunk8(val, w);
}

/*
 * Convert val (0 <= val < 10^8) to 8 zero-padded big-endian ASCII digits
 * ("dddddddd") across (*hi_out, *lo_out).
 */
static __attribute((__always_inline__)) inline
struct dword dds_chunk8_zpad(uint32_t val)
{
    struct dword w = { .lo = 0x30303030, .hi = 0x30303030 };
    return dds_chunk8(val, w);
}

#if 0
/*
 * Exact unsigned 64-bit divmod by 10^8:
 *   Returns Q = n / 10^8, stores R = n % 10^8 in *rem.
 *   Uses K = ceil(2^82 / 5^8) = 0xABCC77118AEF87B8ULL on (n >> 8).
 *   32x32->64 products lower to back-to-back mulhu/mul pairs (FORWARD_MUL).
 */
static uint64_t divmod_1e8_u64(uint64_t n, uint32_t *rem)
{
    const uint32_t K_LO = UINT32_C(0x8AEF87B8);
    const uint32_t K_HI = UINT32_C(0xABCC7711);

    uint64_t m    = n >> 8;
    uint32_t m_lo = (uint32_t)m;
    uint32_t m_hi = (uint32_t)(m >> 32);

    uint64_t p00 = (uint64_t)m_lo * K_LO;
    uint64_t p01 = (uint64_t)m_lo * K_HI;
    uint64_t p10 = (uint64_t)m_hi * K_LO;
    uint64_t p11 = (uint64_t)m_hi * K_HI;

    uint64_t mid = (p00 >> 32) + (uint32_t)p01 + (uint32_t)p10;
    uint64_t hi  = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);

    uint64_t q = hi >> 18;
    *rem = (uint32_t)n - (uint32_t)q * UINT32_C(100000000);
    return q;
}
#else
static uint64_t divmod_1e8_u64(uint64_t n, uint32_t *rem)
{
    uint64_t q = n / UINT32_C(100000000);
    *rem = n % UINT32_C(100000000);
    return q;
}
#endif

/*
 * Convert 32-bit unsigned integer to NUL-terminated decimal ASCII in buf.
 * Buffer must have space for at least 12 bytes and may be written to past
 * the end of the number.
 * Returns pointer to the terminating '\0'.
 */
char *utoa32_dds(uint32_t val, char *buf)
{
    /* Fast path: 1..4 digits (single-register dds.b loop, <= 14 iters) */
    if (likely(val < UINT32_C(10000))) {
        buf = store_trimmed4(buf, dds_chunk4_trim(val));
        *buf = '\0';
        return buf;
    }

    /* Medium path: 5..8 digits (two-register dds.d + dds.b loop, <= 27 iters) */
    if (likely(val < UINT32_C(100000000))) {
	struct dword w =  dds_chunk8_trim(val);
        buf = store_trimmed4(buf, w.hi);
        buf += 4;
        *(uint32_t *)buf = w.lo;
        *buf = '\0';
        return buf;
    }

    /* Full 32-bit path: 9..10 digits (val = q * 10^8 + r, with 1 <= q <= 42) */
    uint32_t q = (uint32_t)((val * UINT64_C(0xABCC7712)) >> 58);
    uint32_t r = val - q * UINT32_C(100000000);

    buf = store_trimmed4(buf, dds_chunk4_trim(q));

    struct dword w = dds_chunk8_zpad(r);
    ((uint32_t *)buf)[0] = w.hi;
    ((uint32_t *)buf)[4] = w.lo;
    buf += 8;
    *buf = '\0';
    return buf;
}

/*
 * Convert 64-bit unsigned integer to NUL-terminated decimal ASCII in buf.
 * Buffer must have space for at least 24 bytes and may be written to past
 * the end of the number.
 * Returns pointer to the terminating '\0'.
 */
char *utoa64_dds(uint64_t val, char *buf)
{
    /* Fast path: values fitting in 32 bits avoid 64-bit division entirely */
    if (likely(!(val >> 32))) {
        return utoa32_dds((uint32_t)val, buf);
    }

    /* Split lowest 8 decimal digits: val = q1 * 10^8 + r0 */
    uint32_t r0;
    uint64_t q1 = divmod_1e8_u64(val, &r0);

    if (likely(q1 < UINT64_C(100000000))) {
        /* 10..16 digits total: format upper 2..8 digits via 32-bit path */
        buf = utoa32_dds((uint32_t)q1, buf);
    } else {
        /* 17..20 digits total: split middle 8 digits (q1 = q2 * 10^8 + r1) */
        uint32_t r1;
        uint32_t q2 = divmod_1e8_u64(q1, &r1); /* 1 <= q2 <= 1844 (< 10^4) */

        buf = store_trimmed4(buf, dds_chunk4_trim(q2));

        struct dword w1 = dds_chunk8_zpad(r1);
	((uint32_t *)buf)[0] = w1.hi;
	((uint32_t *)buf)[1] = w1.lo;
        buf += 8;
    }

    /* Append lowest 8 zero-padded digits */
    struct dword w0 = dds_chunk8_zpad(r0);
    ((uint32_t *)buf)[0] = w0.hi;
    ((uint32_t *)buf)[1] = w0.lo;
    buf += 8;
    *buf = '\0';
    return buf;
}
