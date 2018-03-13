#include <stdio.h>
#include <stdlib.h>
#include <setjmp.h>
#include <sys/time.h>


static jmp_buf env;
static sigjmp_buf sigenv;


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

    BENCH(if (sigsetjmp(env, 0)) return 0)
    printf("Time for sigsetjmp(env, 0):%8.2fns\n", ns);

    BENCH(if (sigsetjmp(env, 1)) return 0)
    printf("Time for sigsetjmp(env, 1):%8.2fns\n", ns);
}
