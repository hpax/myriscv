/* -*- asm -*-
 *
 * Common assembler macros
 */

#ifndef _ASM_H
#define _ASM_H

#define global globl=1

.macro _begin sym:req, class, secpfx, section, secflags, sectype, align=1, globl=0, type=object
    .ifnb \section
    .pushsection "\section","\secflags",@\sectype
    .else
    .ifnb \class
    .pushsection ".\secpfx\().\class\().\sym","\secflags",@\sectype
    .else
    .pushsection ".\secpfx\().\sym","\secflags",@\sectype
    .endif
    .endif
    .balign \align
    .if \globl
    .globl \sym
    .endif
    .type \sym,@\type
\sym :
.endm

.macro end sym:req
    .size \sym,. - \sym
    .popsection
.endm

.macro begin_func sym:req, class, align=4, secpfx=text, section, globl=0, type=function
    _begin \sym, \class, secpfx=\secpfx, secflags=ax, sectype=progbits, section="\section", globl=\globl, align=\align, type=\type
.endm

.macro begin_data sym:req, align=1, class, secpfx=data, section, globl=0, type=object
    _begin \sym, \class, secpfx=\secpfx, secflags=aw, sectype=progbits, section="\section", globl=\globl, align=\align, type=\type
.endm

.macro begin_sdata sym:req, align=1, class, secpfx=sdata, section, globl=0, type=object
    _begin \sym, \class, secpfx=\secpfx, secflags=aw, sectype=progbits, section="\section", globl=\globl, align=\align, type=\type
.endm

.macro begin_const sym:req, align=1, class, secpfx=rodata, section, globl=0, type=object
    _begin \sym, \class, secpfx=\secpfx, secflags=a, sectype=progbits, section="\section", globl=\globl, align=\align, type=\type
.endm

.macro begin_sconst sym:req, align=1, class, secpfx=srodata, section, globl=0, type=object
    _begin \sym, \class, secpfx=\secpfx, secflags=a, sectype=progbits, section="\section", globl=\globl, align=\align, type=\type
.endm

.macro begin_bss sym:req, align=1, class, secpfx=bss, section, globl=0, type=object
    _begin \sym, \class, secpfx=\secpfx, secflags=a, sectype=nobits, section="\section", globl=\globl, align=\align, type=\type
.endm

.macro begin_sbss sym:req, align=1, class, secpfx=sbss, section, globl=0, type=object
    _begin \sym, \class, secpfx=\secpfx, secflags=a, sectype=nobits, section="\section", globl=\globl, align=\align, type=\type
.endm

#endif /* _ASM_H */
