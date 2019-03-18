#include <stdio.h>
#include <stdlib.h>
#include <setjmp.h>
#include <sys/time.h>


static jmp_buf env;
static sigjmp_buf sigenv;


#if __x86_64__
struct cyjmp_struct
{
    size_t rsp;
    size_t rbp;
    size_t rip;
};

static inline int
cysetjmp(struct cyjmp_struct* env)
{
    int res;
    asm goto("\n"
        "\tleaq %l1(%%rip), %%rcx\n"
        "\tmovq %%rsp, 0(%0)\n"
        "\tmovq %%rbp, 8(%0)\n"
        "\tmovq %%rcx, 16(%0)\n"
    :
    : "b" (env)
    : /* Clobber all registers except for rdx, rbx, rsp, rbp */
      "%rax", "%rcx", "%rdx", "%rsi", "%rdi",
      "%r8", "%r9", "%r10", "%r11", "%r12", "%r13", "%r14", "%r15",
      "cc", "memory"
    : res_in_rdx);

    return 0;

res_in_rdx:
    asm volatile("": "=d" (res));
    return res;
}

static struct cyjmp_struct cyenv;
#endif


#define BENCH(CODE) \
    gettimeofday(&tv0, NULL); \
    for (i = 0; i < N; i++) {CODE; asm("");} \
    gettimeofday(&tv1, NULL); \
    ns = (double)(tv1.tv_sec - tv0.tv_sec) * 1e9 + \
         (double)(tv1.tv_usec - tv0.tv_usec) * 1e3; \
    ns /= (double)N;


int main(int argc, char** argv)
{
    long i, N = 10000000;
    if (argc >= 2) N = atol(argv[1]);
    struct timeval tv0, tv1;
    double ns;

    BENCH(if (setjmp(env)) return 0)
    printf("Time for setjmp(env):      %8.2fns\n", ns);

    BENCH(if (sigsetjmp(sigenv, 0)) return 0)
    printf("Time for sigsetjmp(env, 0):%8.2fns\n", ns);

    BENCH(if (sigsetjmp(sigenv, 1)) return 0)
    printf("Time for sigsetjmp(env, 1):%8.2fns\n", ns);

#if __x86_64__
    BENCH(if (cysetjmp(&cyenv)) return 0)
    printf("Time for asm implementation:%7.2fns\n", ns);
#endif
}
