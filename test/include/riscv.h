#ifndef _RISCV_H
#define _RISCV_H

#define MCAUSE_BADPC 0
#define MCAUSE_IBUSERR 1
#define MCAUSE_BADINSN 2
#define MCAUSE_BREAK 3
#define MCAUSE_LALIGN 4
#define MCAUSE_LBUSERR 5
#define MCAUSE_SALIGN 6
#define MCAUSE_SBUSERR 7
#define MCAUSE_ECALLU 8
#define MCAUSE_ECALLS 9
// 10 reserved
#define MCAUSE_ECALLM 11
#define MCAUSE_IPAGE 12
#define MCAUSE_LPAGE 13
// 14 reserved
#define MCAUSE_SPAGE 15

// 16-23 reserved
// 24-31 custom
// 32-47 reserved
// 48-63 custom

#define MCAUSE_IRQ		0x80000000

#define MCAUSE_FIXED_MASK	0x7fffffc0 /* Undefined/zero bits */

#endif	/* _RISCV_H */
