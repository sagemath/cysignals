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
#if HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#if HAVE_TIME_H
#include <time.h>
#endif
#if HAVE_SYS_WAIT_H
#include <sys/wait.h>
#endif
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

// Custom signal handling of other packages.
#define MAX_N_CUSTOM_HANDLERS 16

static int (*custom_signal_is_blocked_pts[MAX_N_CUSTOM_HANDLERS])();
static void (*custom_signal_unblock_pts[MAX_N_CUSTOM_HANDLERS])();
static void (*custom_set_pending_signal_pts[MAX_N_CUSTOM_HANDLERS])(int);
static int n_custom_handlers = 0;

int custom_signal_is_blocked(){
    // Check if a custom block is set.
    for(int i = 0; i < n_custom_handlers; i++){
        if (custom_signal_is_blocked_pts[i]())
            return 1;
    }
    return 0;
}

void custom_signal_unblock(){
    // Unset all custom blocks.
    for(int i = 0; i < n_custom_handlers; i++)
        custom_signal_unblock_pts[i]();
}


void custom_set_pending_signal(int sig){
    // Set a pending signal to custom handlers.
    for(int i = 0; i < n_custom_handlers; i++)
        custom_set_pending_signal_pts[i](sig);
}

#if HAVE_WINDOWS_H
#include <windows.h>
#endif
#if !_WIN32
#include <pthread.h>
#endif
#include "struct_signals.h"


#if ENABLE_DEBUG_CYSIGNALS
static struct timespec sigtime;  /* Time of signal */
#endif

/* The cysigs object (there is a unique copy of this, shared by all
 * Cython modules using cysignals) */
static cysigs_t cysigs;

#if HAVE_SIGPROCMASK
/* The default signal mask during normal operation,
 * initialized by setup_cysignals_handlers(). */
static sigset_t default_sigmask;

/* default_sigmask with SIGHUP, SIGINT, SIGALRM added. */
static sigset_t sigmask_with_sigint;
#endif

#if !_WIN32
/* A trampoline to jump to after handling a signal. */
static cyjmp_buf trampoline_setup;
static sigjmp_buf trampoline;
#endif

static void setup_cysignals_handlers(void);
static void cysigs_interrupt_handler(int sig);
static void cysigs_signal_handler(int sig);

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

static inline void print_stderr(const char* s)
{
    /* Using stdio (fputs, fprintf, fflush) from inside a signal
     * handler is undefined, see signal-safety(7). We use write(2)
     * instead, which is async-signal-safe according to POSIX. */
    write(2, s, strlen(s));
}

/* str should have enough space allocated */
static inline void ulong_to_str(unsigned long val, char *str, int base)
{
    const char xdigits[16] = "0123456789abcdef";
    unsigned long aux;
    int len;

    len = 1; aux = val;
    while (aux /= base) len++;

    str += len; *str = 0;
    do *--str = xdigits[val % base]; while (val /= base);
}

static inline void long_to_str(long val, char *str, int base)
{
    if (val < 0) *str++ = '-';
    ulong_to_str(val < 0 ? -val : val, str, base);
}

static inline void print_stderr_long(long val)
{
    char buf[21];
    long_to_str(val, buf, 10);
    print_stderr(buf);
}

static inline void print_stderr_ptr(void *ptr)
{
    if (!ptr)
        print_stderr("(nil)");
    else {
        char buf[17];
        ulong_to_str((unsigned long)ptr, buf, 16);
        print_stderr("0x");
        print_stderr(buf);
    }
}

/* Reset all signal handlers and the signal mask to their defaults. */
static inline void sig_reset_defaults(void) {
#ifdef SIGHUP
    signal(SIGHUP, SIG_DFL);
#endif
    signal(SIGINT, SIG_DFL);
#ifdef SIGQUIT
    signal(SIGQUIT, SIG_DFL);
#endif
    signal(SIGILL, SIG_DFL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
#ifdef SIGBUS
    signal(SIGBUS, SIG_DFL);
#endif
    signal(SIGSEGV, SIG_DFL);
#ifdef SIGALRM
    signal(SIGALRM, SIG_DFL);
#endif
    signal(SIGTERM, SIG_DFL);
#if HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &default_sigmask, NULL);
#endif
}


/* Call sigdie() with the appropriate error message for the signal, or
 * whether the exception occurred inside our signal handler */
static inline void sigdie_for_sig(int sig, int inside)
{
    sig_reset_defaults();

    /* Quit Python with an appropriate message.
       Make sure to check the standard signals from the C standard first,
       in case systems alias some of these constants. */
    if (inside) {
        if (sig == SIGILL)
            sigdie(sig, "Unhandled SIGILL during signal handling.");
        else if (sig == SIGABRT)
            sigdie(sig, "Unhandled SIGABRT during signal handling.");
        else if (sig == SIGFPE)
            sigdie(sig, "Unhandled SIGFPE during signal handling.");
        else if (sig == SIGSEGV)
            sigdie(sig, "Unhandled SIGSEGV during signal handling.");
    #ifdef SIGBUS
        else if (sig == SIGBUS)
            sigdie(sig, "Unhandled SIGBUS during signal handling.");
    #endif
    #ifdef SIGQUIT
        else if (sig == SIGQUIT)
            sigdie(sig, NULL);
    #endif
        else
            sigdie(sig, "Unknown signal during signal handling.");
    }
    else {
        if (sig == SIGILL)
            sigdie(sig, "Unhandled SIGILL: An illegal instruction occurred.");
        else if (sig == SIGABRT)
            sigdie(sig, "Unhandled SIGABRT: An abort() occurred.");
        else if (sig == SIGFPE)
            sigdie(sig, "Unhandled SIGFPE: An unhandled floating point exception occurred.");
        else if (sig == SIGSEGV)
            sigdie(sig, "Unhandled SIGSEGV: A segmentation fault occurred.");
    #ifdef SIGBUS
        else if (sig == SIGBUS)
            sigdie(sig, "Unhandled SIGBUS: A bus error occurred.");
    #endif
    #ifdef SIGQUIT
        else if (sig == SIGQUIT)
            sigdie(sig, NULL);
    #endif
        else
            sigdie(sig, "Unknown signal received.");
    }
}

/* Cygwin-specific implementation details */
#if defined(__CYGWIN__) && defined(__x86_64__)
#include <w32api/errhandlingapi.h>
LONG WINAPI win32_altstack_handler(EXCEPTION_POINTERS *exc)
{
    int sig = 0;
    /* If we're not handling a signal there is no reason to execute the
     * following code; otherwise it can be run in inappropriate contexts
     * such as when a STATUS_ACCESS_VIOLATION is raised when accessing
     * uncommitted memory in an mmap created with MAP_NORESERVE. See
     * discussion at https://trac.sagemath.org/ticket/27214#comment:11
     *
     * Unfortunately, when handling an exception that occurred while
     * handling another signal, there is currently no way (through Cygwin)
     * to distinguish this case from a legitimate segfault.
     */
    if (!cysigs.inside_signal_handler) {
        return ExceptionContinueExecution;
    }

    /* Logic cribbed from Cygwin for mapping common Windows exception
     * codes to the relevant signal numbers:
     * https://cygwin.com/git/gitweb.cgi?p=newlib-cygwin.git;a=blob;f=winsup/cygwin/exceptions.cc;h=77eff05707f95f7277974fadbccf0e74223d8d1c;hb=HEAD#l650
     * Unfortunately there is no external API by which to access this
     * mapping (a la cygwin_internal(CW_GET_ERRNO_FROM_WINERROR, ...)) */
    switch (exc->ExceptionRecord->ExceptionCode) {
        case STATUS_FLOAT_DENORMAL_OPERAND:
        case STATUS_FLOAT_DIVIDE_BY_ZERO:
        case STATUS_FLOAT_INVALID_OPERATION:
        case STATUS_FLOAT_STACK_CHECK:
        case STATUS_FLOAT_INEXACT_RESULT:
        case STATUS_FLOAT_OVERFLOW:
        case STATUS_FLOAT_UNDERFLOW:
        case STATUS_INTEGER_DIVIDE_BY_ZERO:
        case STATUS_INTEGER_OVERFLOW:
            sig = SIGFPE;
            break;
        case STATUS_ILLEGAL_INSTRUCTION:
        case STATUS_PRIVILEGED_INSTRUCTION:
        case STATUS_NONCONTINUABLE_EXCEPTION:
            sig = SIGILL;
            break;
        case STATUS_TIMEOUT:
            sig = SIGALRM;
            break;
        case STATUS_GUARD_PAGE_VIOLATION:
        case STATUS_DATATYPE_MISALIGNMENT:
            sig = SIGBUS;
            break;
        case STATUS_ACCESS_VIOLATION:
            /* In the case of this last resort exception handling we can
             * probably safely assume this should be a SIGSEGV;
             * other access violations would have already been handled by
             * Cygwin before we wound up on the alternate stack */
        case STATUS_STACK_OVERFLOW:
        case STATUS_ARRAY_BOUNDS_EXCEEDED:
        case STATUS_IN_PAGE_ERROR:
        case STATUS_NO_MEMORY:
        case STATUS_INVALID_DISPOSITION:
            sig = SIGSEGV;
            break;
        case STATUS_CONTROL_C_EXIT:
            sig = SIGINT;
            break;
    }

    sigdie_for_sig(sig, 1);
    return ExceptionContinueExecution;
}


static void cygwin_setup_alt_stack() {
    AddVectoredContinueHandler(0, win32_altstack_handler);
}

#endif  /* CYGWIN && __x86_64__ */

void get_monotonic_time(struct timespec *ts) {
#ifdef _WIN32
    LARGE_INTEGER frequency;
    LARGE_INTEGER counter;

    QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&counter);

    ts->tv_sec = counter.QuadPart / frequency.QuadPart;
    ts->tv_nsec = (counter.QuadPart % frequency.QuadPart) * 1e9 / frequency.QuadPart;
#else
    clock_gettime(CLOCK_MONOTONIC, ts);
#endif
}

/* Handler for SIGHUP, SIGINT, SIGALRM, SIGTERM
 *
 * Inside sig_on() (i.e. when cysigs.sig_on_count is positive), this
 * raises an exception and jumps back to sig_on().
 * Outside of sig_on(), we set Python's interrupt flag using
 * PyErr_SetInterrupt() */
static void cysigs_interrupt_handler(int sig)
{
#if ENABLE_DEBUG_CYSIGNALS
    if (cysigs.debug_level >= 1) {
        print_stderr("\n*** SIG ");
        print_stderr_long(sig);
        if (cysigs.sig_on_count > 0)
            print_stderr(" *** inside sig_on\n");
        else
            print_stderr(" *** outside sig_on\n");
        if (cysigs.debug_level >= 3) print_backtrace();
        /* Store time of this signal, unless there is already a
         * pending signal. */
        if (!cysigs.interrupt_received) get_monotonic_time(&sigtime);
    }
#endif

    if (cysigs.sig_on_count > 0)
    {
        if (!cysigs.block_sigint && !custom_signal_is_blocked())
        {
            /* Raise an exception so Python can see it */
            do_raise_exception(sig);

#if !_WIN32
            /* Jump back to sig_on() (the first one if there is a stack) */
            siglongjmp(trampoline, sig);
#endif
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
    if (
#ifdef SIGHUP
        cysigs.interrupt_received != SIGHUP && 
#endif
        cysigs.interrupt_received != SIGTERM)
    {
        cysigs.interrupt_received = sig;
        custom_set_pending_signal(sig);
    }
}

/* Handler for SIGQUIT, SIGILL, SIGABRT, SIGFPE, SIGBUS, SIGSEGV
 *
 * Inside sig_on() (i.e. when cysigs.sig_on_count is positive), this
 * raises an exception and jumps back to sig_on().
 * Outside of sig_on(), we terminate Python. */
static void cysigs_signal_handler(int sig)
{
    int inside = cysigs.inside_signal_handler;
    cysigs.inside_signal_handler = 1;

    if (inside == 0 && cysigs.sig_on_count > 0 
        #ifdef SIGQUIT
            && sig != SIGQUIT
        #endif
    ) {
        /* We are inside sig_on(), so we can handle the signal! */
#if ENABLE_DEBUG_CYSIGNALS
        if (cysigs.debug_level >= 1) {
            print_stderr("\n*** SIG ");
            print_stderr_long(sig);
            print_stderr(" *** inside sig_on\n");
            if (cysigs.debug_level >= 3) print_backtrace();
            get_monotonic_time(&sigtime);
        }
#endif

        /* Raise an exception so Python can see it */
        do_raise_exception(sig);
    #if !_WIN32
        /* Jump back to sig_on() (the first one if there is a stack) */
        siglongjmp(trampoline, sig);
    #endif
    }
    else
    {
        /* We are outside sig_on() and have no choice but to terminate Python */

        /* Reset all signals to their default behaviour and unblock
         * them in case something goes wrong as of now. */
        sigdie_for_sig(sig, inside);
    }
}

#if !_WIN32
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
static void* _sig_on_trampoline(CYTHON_UNUSED void* dummy)
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
    size_t trampolinestacksize = 1 << 17;

#ifdef PTHREAD_STACK_MIN
    if (trampolinestacksize < (size_t) PTHREAD_STACK_MIN)
        trampolinestacksize = PTHREAD_STACK_MIN;
#endif
    trampolinestack = malloc(trampolinestacksize + 4096);
    if (!trampolinestack) {perror("cysignals malloc"); exit(1);}

    /* Align trampolinestack on a multiple of 4096 bytes.
     * This seems to be needed in particular on OS X. */
    uintptr_t addr = (uintptr_t)trampolinestack;
    addr = ((addr - 1) | 4095) + 1;
    trampolinestack = (void*)addr;

    ret = pthread_attr_init(&attr);
    if (ret) {errno = ret; perror("cysignals pthread_attr_init"); exit(1);}
    ret = pthread_attr_setstack(&attr, trampolinestack, trampolinestacksize);
    if (ret) {errno = ret; perror("cysignals pthread_attr_setstack"); exit(1);}
    ret = pthread_create(&child, &attr, _sig_on_trampoline, NULL);
    if (ret) {errno = ret; perror("cysignals pthread_create"); exit(1);}
    pthread_attr_destroy(&attr);
    ret = pthread_join(child, NULL);
    if (ret) {errno = ret; perror("cysignals pthread_join"); exit(1);}

    if (cysetjmp(cysigs.env) == 0)
    {
        cylongjmp(trampoline_setup, 1);
    }
}
#endif


/* This calls sig_raise_exception() to actually raise the exception. */
static void do_raise_exception(int sig)
{
#if ENABLE_DEBUG_CYSIGNALS
    struct timespec raisetime;
    if (cysigs.debug_level >= 2) {
        get_monotonic_time(&raisetime);
        long delta_ms = (raisetime.tv_sec - sigtime.tv_sec)*1000L + (raisetime.tv_nsec - sigtime.tv_nsec)/1000000L;
        PyGILState_STATE gilstate = PyGILState_Ensure();
        print_stderr("do_raise_exception(sig=");
        print_stderr_long(sig);
        print_stderr(")\nPyErr_Occurred() = ");
        print_stderr_ptr(PyErr_Occurred());
        print_stderr("\nRaising Python exception ");
        print_stderr_long(delta_ms);
        print_stderr("ms after signal...\n");
        PyGILState_Release(gilstate);
    }
#endif

    /* Call Cython function to raise exception */
    sig_raise_exception(sig, cysigs.s);
}


/* This will be called during _sig_on_postjmp() when an interrupt was
 * received *before* the call to sig_on(). */
static void _sig_on_interrupt_received(void)
{
#if HAVE_SIGPROCMASK
    /* Momentarily block signals to avoid race conditions */
    sigset_t oldset;
    sigprocmask(SIG_BLOCK, &sigmask_with_sigint, &oldset);
#endif

    do_raise_exception(cysigs.interrupt_received);
    cysigs.sig_on_count = 0;
    cysigs.interrupt_received = 0;
    custom_set_pending_signal(0);

#if HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &oldset, NULL);
#endif
}

/* Cleanup after cylongjmp() (reset signal mask to the default, set
 * sig_on_count to zero) */
static void _sig_on_recover(void)
{
    cysigs.block_sigint = 0;
    custom_signal_unblock();
    cysigs.sig_on_count = 0;
    cysigs.interrupt_received = 0;
    custom_set_pending_signal(0);

#if HAVE_SIGPROCMASK
    /* Reset signal mask */
    sigprocmask(SIG_SETMASK, &default_sigmask, NULL);
#endif

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
#if HAVE_SIGALTSTACK
    /* Space for the alternate signal stack. The size should be
     * of the form MINSIGSTKSZ + constant. The constant is chosen rather
     * ad hoc but sufficiently large. */
    stack_t ss;
    size_t stack_size = MINSIGSTKSZ + 5120 + BACKTRACELEN * sizeof(void*);
    ss.ss_sp = malloc(stack_size);
    ss.ss_size = stack_size;
    if (ss.ss_sp == NULL) {perror("cysignals malloc alt signal stack"); exit(1);}
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) == -1) {perror("cysignals sigaltstack"); exit(1);}
#endif
#if defined(__CYGWIN__) && defined(__x86_64__)
    cygwin_setup_alt_stack();
#endif
}


static void setup_cysignals_handlers(void)
{
#ifdef _WIN32
    signal(SIGINT, cysigs_interrupt_handler);
    signal(SIGTERM, cysigs_interrupt_handler);
    signal(SIGABRT, cysigs_signal_handler);
#else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));

    /* Reset the cysigs structure */
    memset(&cysigs, 0, sizeof(cysigs));

#if HAVE_SIGPROCMASK
    /* Block non-critical signals during the signal handlers and while
     * cleaning up after handling a signal */
    sigaddset(&sa.sa_mask, SIGHUP);
    sigaddset(&sa.sa_mask, SIGINT);
    sigaddset(&sa.sa_mask, SIGALRM);

    /* Save the default signal mask and apply the signal mask with
     * non-critical signals now to save it on the trampoline.
     * After setting up the trampoline, we reset the signal mask. */
    sigprocmask(SIG_BLOCK, &sa.sa_mask, &default_sigmask);
#endif
    setup_trampoline();
#if HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &default_sigmask, &sigmask_with_sigint);
#endif

    /* Install signal handlers */
    /* Handlers for interrupt-like signals */
    sa.sa_handler = cysigs_interrupt_handler;
    sa.sa_flags = 0;
#ifdef SIGHUP
    if (sigaction(SIGHUP, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#endif
    if (sigaction(SIGINT, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#ifdef SIGALRM
    if (sigaction(SIGALRM, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#endif

    /* Handlers for critical signals */
    sa.sa_handler = cysigs_signal_handler;
    /* Allow signals during signal handling, we have code to deal with
     * this case. */
    sa.sa_flags = SA_NODEFER | SA_ONSTACK;
#ifdef SIGQUIT
    if (sigaction(SIGQUIT, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#endif
    if (sigaction(SIGILL, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
    if (sigaction(SIGABRT, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
    if (sigaction(SIGFPE, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#ifdef SIGBUS
    if (sigaction(SIGBUS, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#endif
    if (sigaction(SIGSEGV, &sa, NULL)) {perror("cysignals sigaction"); exit(1);}
#endif
}


static void print_sep(void)
{
    print_stderr("------------------------------------------------------------------------\n");
}

/* Print a backtrace if supported by libc */
static void print_backtrace()
{
#if HAVE_BACKTRACE
    void* backtracebuffer[BACKTRACELEN];
    int btsize = backtrace(backtracebuffer, BACKTRACELEN);
    if (btsize)
        backtrace_symbols_fd(backtracebuffer, btsize, 2);
    else
        print_stderr("(no backtrace available)\n");
    print_sep();
#endif
}

/* Print a backtrace using gdb */
static inline void print_enhanced_backtrace(void)
{
    /* Bypass Linux Yama restrictions on ptrace() to allow debugging */
    /* See https://www.kernel.org/doc/Documentation/security/Yama.txt */
#ifdef PR_SET_PTRACER
    prctl(PR_SET_PTRACER, PR_SET_PTRACER_ANY, 0, 0, 0);
#endif

    /* Enhanced backtraces are only supported on POSIX systems */
#if HAVE_FORK
    pid_t parent_pid = getpid();
    pid_t pid = fork();

    if (pid < 0)
    {
        /* Failed to fork: no problem, just ignore */
        print_stderr("cysignals fork: ");
        print_stderr(strerror(errno));
        print_stderr("\n");
        return;
    }

    if (pid == 0) { /* child */
        /* Redirect all output to stderr */
        dup2(2, 1);

        /* We deliberately put these variables on the stack to avoid
         * malloc() calls, the heap might be messed up! */
        char* path = "cysignals-CSI";
        char pid_str[32];
        char* argv[5];

        long_to_str(parent_pid, pid_str, 10);

        argv[0] = "cysignals-CSI";
        argv[1] = "--no-color";
        argv[2] = "--pid";
        argv[3] = pid_str;
        argv[4] = NULL;
        execvp(path, argv);
        print_stderr("cysignals failed to execute cysignals-CSI: ");
        print_stderr(strerror(errno));
        print_stderr("\n");
        exit(2);
    }
    /* Wait for cysignals-CSI to finish */
    waitpid(pid, NULL, 0);
#endif

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
        print_stderr(s);
        print_stderr("\n"
            "This probably occurred because a *compiled* module has a bug\n"
            "in it and is not properly wrapped with sig_on(), sig_off().\n"
            "Python will now terminate.\n");
        print_sep();
    }

dienow:
    /* Suicide with signal ``sig``. */
    raise(sig);

    /* We should be dead! */
    exit(128 + sig);
}

/* Finally include the macros and inline functions for use in
 * signals.pyx. These require some of the above functions, therefore
 * this include must come at the end of this file. */
#include "macros.h"
