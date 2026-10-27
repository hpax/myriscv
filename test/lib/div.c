#include "test.h"

typedef struct udiv_t {
    unsigned int q, r;
} udiv_t;

static inline __attribute__((const)) uint32_t mulhu(uint32_t a, uint32_t b)
{
    return ((uint64_t)a * b) >> 32;
}

static inline __attribute__((const)) unsigned int clz(uint32_t x)
{
    return __builtin_clz(x);
}

/* Entry conditions: num >= den, den != 0 */
static inline udiv_t __attribute__((always_inline,const))
udivsi(unsigned int num, unsigned den)
{
    struct udiv_t res;

    // -------------------------------------------------------------
    // 2. Fast Normalization (Zbb) & Reciprocal Estimate
    // -------------------------------------------------------------
    uint32_t clz_den = clz(den);
    uint32_t clz_num = clz(num);
    uint32_t exp_diff = clz_den - clz_num;

    // Normalize den to Q31 format
    uint32_t norm_den = den << clz_den;

    // 2-Instruction initial estimate using bitwise NOT (~a1 >> 1)
    uint32_t recip = (~norm_den) >> 1;

    // -------------------------------------------------------------
    // 3. Newton-Raphson Iteration 1
    // -------------------------------------------------------------
    uint32_t temp_prod = mulhu(norm_den, recip);
    uint32_t temp_sub = 0x20000000 - temp_prod;

    recip = mulhu(recip, temp_sub);
    // Normalize num early to hide multiply latency
    uint32_t norm_num = num << clz_num;
    recip <<= 3; // Rescale fixed point

    // -------------------------------------------------------------
    // 4. Newton-Raphson Iteration 2
    // -------------------------------------------------------------
    temp_prod = mulhu(norm_den, recip);
    temp_sub = 0x20000000 - temp_prod;

    recip = mulhu(recip, temp_sub);
    recip <<= 3; // Final 32-bit reciprocal fraction

    // -------------------------------------------------------------
    // 5. Raw Quotient Calculation
    // -------------------------------------------------------------
    // Raw Quotient = Num * Reciprocal
    uint32_t raw_q = mulhu(norm_num, recip);

    // Final magnitude of Quotient shifted back by exponent difference
    raw_q >>= (31 - exp_diff);

    // -------------------------------------------------------------
    // 6. Remainder Check & Branchless Correction (MyRISCV specific)
    // -------------------------------------------------------------
    uint32_t q_times_b = raw_q * den;
    uint32_t raw_rem = num - q_times_b;

    // Branchless correction utilizing MyRISCV WITH_setext
    // The C relational operator ">=" maps directly to the 'sgeu' instruction.
    uint32_t needs_correction = raw_rem >= den;
    raw_q += needs_correction;

    // If corrected (1), subtract den. Else (0), subtract 0.
    // The ternary operator mapped against 0 will natively compile to the
    // 'czero.eqz' instruction from the Zicond extension.
    uint32_t rem_correction = needs_correction ? den : 0;
    raw_rem -= rem_correction;

    // -------------------------------------------------------------
    // 7. Output Population
    // -------------------------------------------------------------
    res.q = raw_q;
    res.r = raw_rem;

    return res;
}

__attribute__((hot)) int
__divsi3(int num_in, int den_in)
{
    if (unlikely(!den_in))
	return -1;

    uint32_t abs_num = (num_in < 0) ? -num_in : num_in;
    uint32_t abs_den  = (den_in < 0)  ? -den_in  : den_in;
    int q_sign = num_in ^ den_in;

    if (unlikely(abs_num < abs_den))
	return 0;

    struct udiv_t ures = udivsi(abs_num, abs_den);

    return q_sign < 0 ? -ures.q : ures.q;
}

__attribute__((hot)) int
__remsi3(int num_in, int den_in)
{
    uint32_t abs_num = (num_in < 0) ? -num_in : num_in;
    uint32_t abs_den  = (den_in < 0)  ? -den_in  : den_in;

    if (unlikely(!den_in) || unlikely(abs_num < abs_den))
	return num_in;

    struct udiv_t ures = udivsi(abs_num, abs_den);

    return num_in < 0 ? -ures.r : ures.r;
}

__attribute__((hot)) unsigned int
__udivsi3(unsigned int num, unsigned int den)
{
    if (unlikely(!den))
	return -1;
    if (unlikely(num < den))
	return 0;

    return udivsi(num, den).q;
}

__attribute__((hot)) unsigned int
__uremsi3(unsigned int num, unsigned int den)
{
    if (unlikely(!den) || unlikely(num < den))
	return num;

    return udivsi(num, den).r;
}

__attribute__((hot)) unsigned int
__udivmodsi4(unsigned int num, unsigned den, unsigned int *rem)
{
    if (unlikely(!den)) {
	*rem = num;
	return -1;
    }
    if (unlikely(num < den)) {
	*rem = num;
	return 0;
    }

    struct udiv_t ures = udivsi(num, den);

    *rem = ures.r;
    return ures.q;
}

__attribute__((hot)) int
__divmodsi4(int num_in, int den_in, int *rem)
{
    if (unlikely(!den_in)) {
	*rem = num_in;
	return -1;
    }

    uint32_t abs_num = (num_in < 0) ? -num_in : num_in;
    uint32_t abs_den  = (den_in < 0)  ? -den_in  : den_in;
    int q_sign = num_in ^ den_in;

    if (unlikely(abs_num < abs_den)) {
	*rem = num_in;
	return 0;
    }

    struct udiv_t ures = udivsi(abs_num, abs_den);

    *rem = num_in < 0 ? -ures.r : ures.r;
    return q_sign < 0 ? -ures.q : ures.q;
}
