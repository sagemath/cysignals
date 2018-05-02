/*
Interrupt and signal handling for Cython
*/

/*****************************************************************************
 *       Copyright (C) 2006 William Stein <wstein@gmail.com>
 *                     2006-2016 Martin Albrecht <martinralbrecht+cysignals@gmail.com>
 *                     2010-2018 Jeroen Demeyer <J.Demeyer@UGent.be>
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


#if __USE_FORTIFY_LEVEL
#error "cysignals must be compiled without _FORTIFY_SOURCE"
#endif


#include "config.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <pthread.h>
#if HAVE_UNISTD_H
#include <unistd.h>
#endif
#if HAVE_EXECINFO_H
#include <execinfo.h>
#endif
#if HAVE_SYS_PRCTL_H
#include <sys/prctl.h>
#endif
#include <Python.h>
#if HAVE_PARI
#include <pari/pari.h>
#else
/* Fake PARI variables */
static int PARI_SIGINT_block = 0;
static int PARI_SIGINT_pending = 0;
#endif
#include "struct_signals.h"

/* Some systems have MAP_ANON but not MAP_ANONYMOUS */
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif


#if ENABLE_DEBUG_CYSIGNALS
static struct timeval sigtime;  /* Time of signal */
#endif

/* The cysigs object (there is a unique copy of this, shared by all
 * Cython modules using cysignals) */
static cysigs_t cysigs;

/* The default signal mask during normal operation,
 * initialized by setup_cysignals_handlers(). */
static sigset_t default_sigmask;

/* A trampoline to jump to after handling a signal. */
static cyjmp_buf trampoline_setup;
static sigjmp_buf trampoline;

/* default_sigmask with SIGHUP, SIGINT, SIGALRM added. */
static sigset_t sigmask_with_sigint;


static void do_raise_exception(int sig);
static void sigdie(int sig, const char* s);

#define BACKTRACELEN 1024
static void print_backtrace(void);

/* Implemented in signals.pyx */
static int sig_raise_exception(int sig, const char* msg);


/* Do whatever is needed to reset the CPU to a sane state after
 * handling a signals.  In particular on x86 CPUs, we need to clear
 * the FPU (this is needed after MMX instructions have been used or
 * if an interrupt occurs during an FPU computation).
 * Linux and OS X 10.6 do this as part of their signals implementation,
 * but Solaris doesn't.  Since this code is called only when handling a
 * signal (which should be very rare), it's better to play safe and
 * always execute this instead of special-casing based on the operating
 * system.
 * See http://trac.sagemath.org/sage_trac/ticket/12873
 */
static inline void reset_CPU(void)
{
#if HAVE_EMMS
    /* Clear FPU tag word */
    asm("emms");
#endif
}


/* Reset all signal handlers and the signal mask to their defaults. */
static inline void sig_reset_defaults(void) {
    signal(SIGHUP, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGQUIT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGALRM, SIG_DFL);
    signal(SIGTERM, SIG_DFL);
    sigprocmask(SIG_SETMASK, &default_sigmask, NULL);
}


/* Call sigdie() with the appropriate error message for the signal, or
 * whether the exception occurred inside our signal handler */
static inline void sigdie_for_sig(int sig, int inside)
{
    sig_reset_defaults();
    if (inside) sigdie(sig, "An error occurred during signal handling.");

    /* Quit Python with an appropriate message. */
    switch(sig)
    {
        case SIGQUIT:
            sigdie(sig, NULL);
            break;  /* This will not be reached */
        case SIGILL:
            sigdie(sig, "Unhandled SIGILL: An illegal instruction occurred.");
            break;  /* This will not be reached */
        case SIGABRT:
            sigdie(sig, "Unhandled SIGABRT: An abort() occurred.");
            break;  /* This will not be reached */
        case SIGFPE:
            sigdie(sig, "Unhandled SIGFPE: An unhandled floating point exception occurred.");
            break;  /* This will not be reached */
        case SIGBUS:
            sigdie(sig, "Unhandled SIGBUS: A bus error occurred.");
            break;  /* This will not be reached */
        case SIGSEGV:
            sigdie(sig, "Unhandled SIGSEGV: A segmentation fault occurred.");
            break;  /* This will not be reached */
    };
    sigdie(sig, "Unknown signal received.\n");
}


/* Additional platform-specific implementation code */
#if defined(__CYGWIN__)
#include "implementation_cygwin.c"
#endif


/* Handler for SIGHUP, SIGINT, SIGALRM
 *
 * Inside sig_on() (i.e. when cysigs.sig_on_count is positive), this
 * raises an exception and jumps back to sig_on().
 * Outside of sig_on(), we set Python's interrupt flag using
 * PyErr_SetInterrupt() */
static void cysigs_interrupt_handler(int sig)
{
#if ENABLE_DEBUG_CYSIGNALS
    if (cysigs.debug_level >= 1) {
        fprintf(stderr, "\n*** SIG %i *** %s sig_on\n", sig, (cysigs.sig_on_count > 0) ? "inside" : "outside");
        if (cysigs.debug_level >= 3) print_backtrace();
        fflush(stderr);
        /* Store time of this signal, unless there is already a
         * pending signal. */
        if (!cysigs.interrupt_received) gettimeofday(&sigtime, NULL);
    }
#endif

    if (cysigs.sig_on_count > 0)
    {
        if (!cysigs.block_sigint && !PARI_SIGINT_block)
        {
            /* Raise an exception so Python can see it */
            do_raise_exception(sig);

            /* Jump back to sig_on() (the first one if there is a stack) */
            siglongjmp(trampoline, sig);
        }
    }
    else
    {
        /* Set the Python interrupt indicator, which will cause the
         * Python-level interrupt handler in cysignals/signals.pyx to
         * be called. */
        PyErr_SetInterrupt();
    }

    /* If we are here, we cannot handle the interrupt immediately, so
     * we store the signal number for later use.  But make sure we
     * don't overwrite a SIGHUP or SIGTERM which we already received. */
    if (cysigs.interrupt_received != SIGHUP && cysigs.interrupt_received != SIGTERM)
    {
        cysigs.interrupt_received = sig;
        PARI_SIGINT_pending = sig;
    }
}

/* Handler for SIGQUIT, SIGILL, SIGABRT, SIGFPE, SIGBUS, SIGSEGV
 *
 * Inside sig_on() (i.e. when cysigs.sig_on_count is positive), this
 * raises an exception and jumps back to sig_on().
 * Outside of sig_on(), we terminate Python. */
static void cysigs_signal_handler(int sig)
{
    sig_atomic_t inside = cysigs.inside_signal_handler;
    cysigs.inside_signal_handler = 1;

    if (inside == 0 && cysigs.sig_on_count > 0 && sig != SIGQUIT)
    {
        /* We are inside sig_on(), so we can handle the signal! */
#if ENABLE_DEBUG_CYSIGNALS
        if (cysigs.debug_level >= 1) {
            fprintf(stderr, "\n*** SIG %i *** inside sig_on\n", sig);
            if (cysigs.debug_level >= 3) print_backtrace();
            fflush(stderr);
            gettimeofday(&sigtime, NULL);
        }
#endif

        /* Raise an exception so Python can see it */
        do_raise_exception(sig);

        /* Jump back to sig_on() (the first one if there is a stack) */
        siglongjmp(trampoline, sig);
    }
    else
    {
        /* We are outside sig_on() and have no choice but to terminate Python */

        /* Reset all signals to their default behaviour and unblock
         * them in case something goes wrong as of now. */
        sigdie_for_sig(sig, inside);
    }
}


/* A trampoline to jump to after handling a signal.
 *
 * The jump to sig_on() uses cylongjmp(), which does not restore the
 * signal context. This is done for efficiency, as cysetjmp() is
 * significantly faster this way. But in order to get away from our alt
 * stack after handling a signal, we need an additional siglongjmp()
 * call to restore the signal context. This is the call from the signal
 * handler to this trampoline function.
 *
 * Setting this up requires some trickery:
 * (A) create a separate stack for this trampoline function
 * (B) start a new thread using this stack
 * (C) set a jump point on the trampoline stack using cysetjmp()
 * (D) exit the thread
 * (E) back in the main thread, jump to the point set at (C). Now we are
 *     on the trampoline stack
 * (F) set a jump point with savesigs=1. This is where we will jump to
 *     after handling a signal
 * (G) jump back to the main program
 *
 * NOTE: it may look strange to use threads for this, but there are not
 * a lot of good ways to get code running on an arbitrary stack. In
 * fact, POSIX recommends threads in
 * http://pubs.opengroup.org/onlinepubs/009695299/functions/makecontext.html
 */
static void* _sig_on_trampoline(void* dummy)
{
    register int sig;

    /* Reserve some unused stack space to prevent pthread_exit() from
     * clobbering the stack that we care about. This is in particular
     * needed on certain older GNU/Linux systems:
     * https://trac.sagemath.org/ticket/25092#comment:6 */
    char stack_guard[2048];

    if (cysetjmp(trampoline_setup) == 0)
        /* The argument to pthread_exit() does not matter. We use
         * stack_guard to prevent GCC from optimizing away the
         * stack_guard variable. */
        pthread_exit(stack_guard);

    sig = sigsetjmp(trampoline, 1);
    reset_CPU();
    cylongjmp(cysigs.env, sig);
}


static void setup_trampoline(void)
{
    int ret;
    pthread_t child;
    pthread_attr_t attr;
    void* trampolinestack;
    size_t trampolinestacksize = 1 << 16;

    while (trampolinestacksize < PTHREAD_STACK_MIN) trampolinestacksize *= 2;
    trampolinestack = mmap(NULL, trampolinestacksize,
            PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (trampolinestack == MAP_FAILED) {perror("mmap"); exit(1);}

    ret = pthread_attr_init(&attr);
    if (ret) {errno = ret; perror("pthread_attr_init"); exit(1);}
    ret = pthread_attr_setstack(&attr, trampolinestack, trampolinestacksize);
    if (ret) {errno = ret; perror("pthread_attr_setstack"); exit(1);}
    ret = pthread_create(&child, &attr, _sig_on_trampoline, NULL);
    if (ret) {errno = ret; perror("pthread_create"); exit(1);}
    pthread_attr_destroy(&attr);
    ret = pthread_join(child, NULL);
    if (ret) {errno = ret; perror("pthread_join"); exit(1);}

    if (cysetjmp(cysigs.env) == 0)
    {
        cylongjmp(trampoline_setup, 1);
    }
}


/* This calls sig_raise_exception() to actually raise the exception. */
static void do_raise_exception(int sig)
{
#if ENABLE_DEBUG_CYSIGNALS
    struct timeval raisetime;
    if (cysigs.debug_level >= 2) {
        gettimeofday(&raisetime, NULL);
        long delta_ms = (raisetime.tv_sec - sigtime.tv_sec)*1000L + ((long)raisetime.tv_usec - (long)sigtime.tv_usec)/1000;
        PyGILState_STATE gilstate = PyGILState_Ensure();
        fprintf(stderr, "do_raise_exception(sig=%i)\nPyErr_Occurred() = %p\nRaising Python exception %li ms after signal...\n",
            sig, PyErr_Occurred(), delta_ms);
        PyGILState_Release(gilstate);
        fflush(stderr);
    }
#endif

    /* Call Cython function to raise exception */
    sig_raise_exception(sig, cysigs.s);
}


/* This will be called during _sig_on_postjmp() when an interrupt was
 * received *before* the call to sig_on(). */
static void _sig_on_interrupt_received(void)
{
    /* Momentarily block signals to avoid race conditions */
    sigset_t oldset;
    sigprocmask(SIG_BLOCK, &sigmask_with_sigint, &oldset);

    do_raise_exception(cysigs.interrupt_received);
    cysigs.sig_on_count = 0;
    cysigs.interrupt_received = 0;
    PARI_SIGINT_pending = 0;

    sigprocmask(SIG_SETMASK, &oldset, NULL);
}

/* Cleanup after cylongjmp() (reset signal mask to the default, set
 * sig_on_count to zero) */
static void _sig_on_recover(void)
{
    cysigs.block_sigint = 0;
    PARI_SIGINT_block = 0;
    cysigs.sig_on_count = 0;
    cysigs.interrupt_received = 0;
    PARI_SIGINT_pending = 0;

    /* Reset signal mask */
    sigprocmask(SIG_SETMASK, &default_sigmask, NULL);
    cysigs.inside_signal_handler = 0;
}

/* Give a warning that sig_off() was called without sig_on() */
static void _sig_off_warning(const char* file, int line)
{
    char buf[320];
    snprintf(buf, sizeof(buf), "sig_off() without sig_on() at %s:%i", file, line);

    /* Raise a warning with the Python GIL acquired */
    PyGILState_STATE gilstate_save = PyGILState_Ensure();
    PyErr_WarnEx(PyExc_RuntimeWarning, buf, 2);
    PyGILState_Release(gilstate_save);

    print_backtrace();
}


static void setup_alt_stack(void)
{
    /* Static space for the alternate signal stack. The size should be
     * of the form MINSIGSTKSZ + constant. The constant is chosen rather
     * ad hoc but sufficiently large. */
    static char alt_stack[MINSIGSTKSZ + 5120 + BACKTRACELEN * sizeof(void*)];

    stack_t ss;
    ss.ss_sp = alt_stack;
    ss.ss_size = sizeof(alt_stack);
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) == -1) {perror("sigaltstack"); exit(1);}
#if defined(__CYGWIN__) && defined(__x86_64__)
    cygwin_setup_alt_stack();
#endif
}


static void setup_cysignals_handlers(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));

    /* Reset the cysigs structure */
    memset(&cysigs, 0, sizeof(cysigs));

    /* Block non-critical signals during the signal handlers and while
     * cleaning up after handling a signal */
    sigaddset(&sa.sa_mask, SIGHUP);
    sigaddset(&sa.sa_mask, SIGINT);
    sigaddset(&sa.sa_mask, SIGALRM);

    /* Save the default signal mask and apply the signal mask with
     * non-critical signals now to save it on the trampoline.
     * After setting up the trampoline, we reset the signal mask. */
    sigprocmask(SIG_BLOCK, &sa.sa_mask, &default_sigmask);
    setup_trampoline();
    sigprocmask(SIG_SETMASK, &default_sigmask, &sigmask_with_sigint);

    /* Install signal handlers */
    /* Handlers for interrupt-like signals */
    sa.sa_handler = cysigs_interrupt_handler;
    sa.sa_flags = 0;
    if (sigaction(SIGHUP, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGINT, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGALRM, &sa, NULL)) {perror("sigaction"); exit(1);}

    /* Handlers for critical signals */
    sa.sa_handler = cysigs_signal_handler;
    /* Allow signals during signal handling, we have code to deal with
     * this case. */
    sa.sa_flags = SA_NODEFER | SA_ONSTACK;
    if (sigaction(SIGQUIT, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGILL, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGABRT, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGFPE, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGBUS, &sa, NULL)) {perror("sigaction"); exit(1);}
    if (sigaction(SIGSEGV, &sa, NULL)) {perror("sigaction"); exit(1);}
}


static void print_sep(void)
{
    fputs("------------------------------------------------------------------------\n",
            stderr);
    fflush(stderr);
}

/* Print a backtrace if supported by libc */
static void print_backtrace()
{
    void* backtracebuffer[BACKTRACELEN];
    fflush(stderr);
#if HAVE_BACKTRACE
    int btsize = backtrace(backtracebuffer, BACKTRACELEN);
    if (btsize)
        backtrace_symbols_fd(backtracebuffer, btsize, 2);
    else
        fputs("(no backtrace available)\n", stderr);
    print_sep();
#endif
}

/* Print a backtrace using gdb */
static void print_enhanced_backtrace(void)
{
    /* Bypass Linux Yama restrictions on ptrace() to allow debugging */
    /* See https://www.kernel.org/doc/Documentation/security/Yama.txt */
#ifdef PR_SET_PTRACER
    prctl(PR_SET_PTRACER, PR_SET_PTRACER_ANY, 0, 0, 0);
#endif

    /* Flush all buffers before forking */
    fflush(stdout);
    fflush(stderr);

    pid_t parent_pid = getpid();
    pid_t pid = fork();

    if (pid < 0)
    {
        /* Failed to fork: no problem, just ignore */
        perror("fork");
        return;
    }

    if (pid == 0) { /* child */
        /* Redirect all output to stderr */
        dup2(2, 1);

        /* We deliberately put these variables on the stack to avoid
         * malloc() calls, the heap might be messed up! */
        char path[1024];
        char pid_str[32];
        char* argv[5];

        snprintf(path, sizeof(path), "cysignals-CSI");
        snprintf(pid_str, sizeof(pid_str), "%i", parent_pid);

        argv[0] = "cysignals-CSI";
        argv[1] = "--no-color";
        argv[2] = "--pid";
        argv[3] = pid_str;
        argv[4] = NULL;
        execvp(path, argv);
        perror("Failed to execute cysignals-CSI");
        exit(2);
    }
    /* Wait for cysignals-CSI to finish */
    waitpid(pid, NULL, 0);

    print_sep();
}


/* Print a message s and kill ourselves with signal sig */
static void sigdie(int sig, const char* s)
{
    if (getenv("CYSIGNALS_CRASH_QUIET")) goto dienow;

    print_sep();
    print_backtrace();

#if ENABLE_DEBUG_CYSIGNALS
    /* Interrupt debugging is enabled, don't do enhanced backtraces as
     * the user is probably using other debugging tools and we don't
     * want to interfere with that. */
#else
#if !(defined(__APPLE__) || defined(__CYGWIN__))
    /* See http://trac.sagemath.org/13889 for how Apple screwed this up */
    /* On Cygwin this has never quite worked, and in particular when run
       from the altstack handler it just results in fork errors, so disable
       this feature for now */
    if (getenv("CYSIGNALS_CRASH_NDEBUG") == NULL)
        print_enhanced_backtrace();
#endif
#endif

    if (s) {
        fprintf(stderr,
            "%s\n"
            "This probably occurred because a *compiled* module has a bug\n"
            "in it and is not properly wrapped with sig_on(), sig_off().\n"
            "Python will now terminate.\n", s);
        print_sep();
    }

dienow:
    /* Suicide with signal ``sig``. We intentionally use kill(getpid())
     * instead of raise() because we want to kill all threads in a
     * multi-threaded program. */
    kill(getpid(), sig);

    /* We should be dead! */
    exit(128 + sig);
}


/* Finally include the macros and inline functions for use in
 * signals.pyx. These require some of the above functions, therefore
 * this include must come at the end of this file. */
#include "macros.h"
