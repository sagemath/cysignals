#undef _FORTIFY_SOURCE
#undef _FORTIFY_SOURCE
#undef _FORTIFY_SOURCE

#include <stdio.h>
#include <setjmp.h>
#include <sys/time.h>

static jmp_buf env;
static sigjmp_buf sigenv;

int main(int argc, char** argv)
{
    unsigned int i, N = 10000000;
    struct timeval tv0, tv1;
    double t;

    gettimeofday(&tv0, NULL);
    for (i = 0; i < N; i++)
    {
        if (setjmp(env)) return 0;
        asm("");
    }
    gettimeofday(&tv1, NULL);
    
    t = (double)(tv1.tv_sec - tv0.tv_sec) * 1e0;
    t += (double)(tv1.tv_usec - tv0.tv_usec) * 1e-6;
    printf("Time per iteration for setjmp():    %8.2fns\n", 1e9 * t/(double)N);

    gettimeofday(&tv0, NULL);
    for (i = 0; i < N; i++)
    {
        if (sigsetjmp(env, 0)) return 0;
        asm("");
    }
    gettimeofday(&tv1, NULL);
    
    t = (double)(tv1.tv_sec - tv0.tv_sec) * 1e0;
    t += (double)(tv1.tv_usec - tv0.tv_usec) * 1e-6;
    printf("Time per iteration for sigsetjmp(0):%8.2fns\n", 1e9 * t/(double)N);

    gettimeofday(&tv0, NULL);
    for (i = 0; i < N; i++)
    {
        if (sigsetjmp(env, 1)) return 0;
        asm("");
    }
    gettimeofday(&tv1, NULL);
    
    t = (double)(tv1.tv_sec - tv0.tv_sec) * 1e0;
    t += (double)(tv1.tv_usec - tv0.tv_usec) * 1e-6;
    printf("Time per iteration for sigsetjmp(1):%8.2fns\n", 1e9 * t/(double)N);
}
