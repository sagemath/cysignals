/*****************************************************************************
 *       Copyright (C) 2006 William Stein <wstein@gmail.com>
 *                     2006 Martin Albrecht <martinralbrecht+cysignals@gmail.com>
 *                     2010-2019 Jeroen Demeyer <J.Demeyer@UGent.be>
 *
 * cysignals is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * cysignals is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with cysignals.  If not, see <http://www.gnu.org/licenses/>.
 *
 ****************************************************************************/

#ifndef CYSIGNALS_CYSETJMP_H
#define CYSIGNALS_CYSETJMP_H


#include <stddef.h>
#include <setjmp.h>


#if CYSIGNALS_ASM_CYSETJMP
#ifdef __x86_64__
/*
 * x86_64 assembly implementation of cysetjmp(): we store the registers
 * rsp and rbp and the instruction pointer.
 *
 * rbx is used to pass a pointer to a cyjmp_struct,
 * rdx is the value passed to cylongjmp().
 */
struct cyjmp_struct
{
    size_t rsp;
    size_t rbp;
    size_t rip;
};

typedef struct cyjmp_struct cyjmp_buf[1];

static inline int __attribute__((always_inline))
cysetjmp(struct cyjmp_struct* env)
{
    int res;
    __asm__ goto("\n"
        "\tleaq %l1(%%rip), %%rcx\n"
        "\tmovq %%rsp, 0(%0)\n"
        "\tmovq %%rbp, 8(%0)\n"
        "\tmovq %%rcx, 16(%0)\n"
    :
    : "b" (env)
    : /* Clobber all registers except for rbx, rsp, rbp */
      "%rax", "%rcx", "%rdx", "%rsi", "%rdi",
      "%r8", "%r9", "%r10", "%r11", "%r12", "%r13", "%r14", "%r15",
      "%mm0", "%mm1", "%mm2", "%mm3", "%mm4", "%mm5", "%mm6", "%mm7",
      "%xmm0", "%xmm1", "%xmm2", "%xmm3", "%xmm4", "%xmm5", "%xmm6", "%xmm7",
      "%xmm8", "%xmm9", "%xmm10", "%xmm11", "%xmm12", "%xmm13", "%xmm14", "%xmm15",
#ifdef __AVX__
      "%ymm0", "%ymm1", "%ymm2", "%ymm3", "%ymm4", "%ymm5", "%ymm6", "%ymm7",
      "%ymm8", "%ymm9", "%ymm10", "%ymm11", "%ymm12", "%ymm13", "%ymm14", "%ymm15",
#endif
#ifdef __AVX512F__
      "%xmm16", "%xmm17", "%xmm18", "%xmm19", "%xmm20", "%xmm21", "%xmm22", "%xmm23",
      "%xmm24", "%xmm25", "%xmm26", "%xmm27", "%xmm28", "%xmm29", "%xmm30", "%xmm31",
      "%ymm16", "%ymm17", "%ymm18", "%ymm19", "%ymm20", "%ymm21", "%ymm22", "%ymm23",
      "%ymm24", "%ymm25", "%ymm26", "%ymm27", "%ymm28", "%ymm29", "%ymm30", "%ymm31",
      "%zmm0", "%zmm1", "%zmm2", "%zmm3", "%zmm4", "%zmm5", "%zmm6", "%zmm7",
      "%zmm8", "%zmm9", "%zmm10", "%zmm11", "%zmm12", "%zmm13", "%zmm14", "%zmm15",
      "%zmm16", "%zmm17", "%zmm18", "%zmm19", "%zmm20", "%zmm21", "%zmm22", "%zmm23",
      "%zmm24", "%zmm25", "%zmm26", "%zmm27", "%zmm28", "%zmm29", "%zmm30", "%zmm31",
#endif
      "cc", "memory"
    : res_in_rdx);

    return 0;

res_in_rdx:
    __attribute__((cold));
    __asm__ volatile("": "=d" (res));
    return res;
}

static void __attribute__((noreturn))
cylongjmp(const struct cyjmp_struct* env, int val)
{
    if (val == 0) val = 1;

    __asm__ volatile("\n"
        "\tmovq 16(%0), %%rcx\n"
        "\tmovq 8(%0), %%rbp\n"
        "\tmovq 0(%0), %%rsp\n"
        "\tjmp *%%rcx\n"
    :
    : "b" (env), "d" (val));
    __builtin_unreachable();
}
#else
#error "assembly implementation of cysetjmp requires x86_64"
#endif
#elif CYSIGNALS_USE_SIGSETJMP
#define cyjmp_buf sigjmp_buf
#define cysetjmp(env) sigsetjmp(env, 0)
#define cylongjmp(env, val) siglongjmp(env, val)
#else
#define cyjmp_buf jmp_buf
#define cysetjmp(env) setjmp(env)
#define cylongjmp(env, val) longjmp(env, val)
#endif

#endif
