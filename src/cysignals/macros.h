/*
Interrupt and signal handling for Cython.

This code distinguishes between two kinds of signals:

(1) interrupt-like signals: SIGINT, SIGALRM, SIGHUP.  The word
"interrupt" refers to any of these signals.  These need not be handled
immediately, we might handle them at a suitable later time, outside of
sig_block() and with the Python GIL acquired.  SIGINT raises a
KeyboardInterrupt (as usual in Python), SIGALRM raises AlarmInterrupt
(a custom exception inheriting from KeyboardInterrupt), while SIGHUP
raises SystemExit, causing Python to exit.  The latter signal also
redirects stdin from /dev/null, to cause interactive sessions to exit.

(2) critical signals: SIGQUIT, SIGILL, SIGABRT, SIGFPE, SIGBUS, SIGSEGV.
These are critical because they cannot be ignored.  If they happen
outside of sig_on(), we can only exit Python with the dreaded
"unhandled SIG..." message.  Inside of sig_on(), they can be handled
and raise various exceptions (see cysignals/signals.pyx).  SIGQUIT
will never be handled and always causes Python to exit.

*/

/*****************************************************************************
 *       Copyright (C) 2006 William Stein <wstein@gmail.com>
 *                     2006 Martin Albrecht <martinralbrecht+cysignals@gmail.com>
 *                     2010-2016 Jeroen Demeyer <J.Demeyer@UGent.be>
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


#ifndef CYSIGNALS_MACROS_H
#define CYSIGNALS_MACROS_H

#include <setjmp.h>
#include <signal.h>
#include "struct_signals.h"

#ifdef __cplusplus
extern "C" {
#endif


/**********************************************************************
 * HELPER FUNCTIONS                                                   *
 **********************************************************************/

/* Send a signal to the calling process. The POSIX raise() function
 * sends a signal to the calling thread, while kill() typically sends
 * a signal to the main thread (although this is not guaranteed by the
 * POSIX standard) */
#if HAVE_KILL
#define proc_raise(sig)  kill(getpid(), sig)
#else
/* On Windows, raise() actually signals the process */
#define proc_raise(sig)  raise(sig)
#endif

/**********************************************************************
 * IMPLEMENTATION OF SIG_ON/SIG_OFF                                   *
 **********************************************************************/

/*
 * Implementation of sig_on().  Applications should not use this
 * directly, use sig_on() or sig_str() instead.
 *
 * _sig_on_(message) is a macro which pretends to be a function.
 * Since this is declared as "cdef except 0", Cython will know that an
 * exception occurred if the value of _sig_on_() is 0 (false).
 *
 * INPUT:
 *
 *  - message -- a string to be displayed as error message when the code
 *    between sig_on() and sig_off() fails and raises an exception.
 *
 * OUTPUT: zero if an exception occurred, non-zero otherwise.
 *
 * The function cysetjmp() in the _sig_on_() macro can return:
 *  - zero: this happens in the actual sig_on() call. cysetjmp() sets
 *    up the address for the signal handler to jump to.  The
 *    program continues normally.
 *  - a signal number (e.g. 2 for SIGINT), assumed to be strictly
 *    positive: the cysignals signal handler handled a signal.  Since
 *    _sig_on_() will return 0 in this case, the Exception (raised by
 *    cysigs_signal_handler) will be detected by Cython.
 *  - a negative number: this is assumed to come from sig_retry().  In
 *    this case, the program continues as if nothing happened between
 *    sig_on() and sig_retry().
 *
 * We cannot simply put cysetjmp() in a function, because when that
 * function returns, we would lose the stack frame to cylongjmp() to.
 * That's why we need this hackish macro.  We use the fact that || is
 * a short-circuiting operator (the second argument is only evaluated
 * if the first returns 0).
 */

#define _sig_on_(message) ( unlikely(_sig_on_prejmp(message, __FILE__, __LINE__)) || _sig_on_postjmp(cysetjmp(cysigs.env)) )

/*
 * Set message, return 0 if we need to cysetjmp(), return 1 otherwise.
 */
static inline int _sig_on_prejmp(const char* message, const char* file, int line)
{
    cysigs.s = message;
#if ENABLE_DEBUG_CYSIGNALS
    if (cysigs.debug_level >= 4)
    {
        fprintf(stderr, "sig_on (count = %i) at %s:%i\n",
                (int)cysigs.sig_on_count+1, file, line);
        fflush(stderr);
    }
    if (cysigs.block_sigint && cysigs.sig_on_count <= 0)
    {
        fprintf(stderr, "\n*** ERROR *** sig_on() with sig_on_count = %i, block_sigint = %i\n",
                (int)cysigs.sig_on_count, (int)cysigs.block_sigint);
        print_backtrace();
    }
#endif
    if (cysigs.sig_on_count > 0)
    {
        cysigs.sig_on_count++;
        return 1;
    }

    /* At this point, cysigs.sig_on_count == 0 */
    return 0;
}


/*
 * Process the return value of cysetjmp().
 * Return 0 if there was an exception, 1 otherwise.
 */
static inline int _sig_on_postjmp(int jmpret)
{
    if (unlikely(jmpret > 0))
    {
        /* An exception occurred */
        _sig_on_recover();
        return 0;
    }

    /* When we are here, it's either the original sig_on() call or we
     * got here after sig_retry(). */
    cysigs.sig_on_count = 1;

    /* Check whether we received an interrupt before this point.
     * cysigs.interrupt_received can only be set by the interrupt
     * handler if cysigs.sig_on_count is zero.  Because of that and
     * because cysigs.sig_on_count and cysigs.interrupt_received are
     * volatile, we can safely evaluate cysigs.interrupt_received here
     * without race conditions. */
    if (unlikely(cysigs.interrupt_received))
    {
        _sig_on_interrupt_received();
        return 0;
    }

    return 1;
}


/*
 * Implementation of sig_off().  Applications should not use this
 * directly, use sig_off() instead.
 */
static inline void _sig_off_(const char* file, int line)
{
#if ENABLE_DEBUG_CYSIGNALS
    if (cysigs.debug_level >= 4)
    {
        fprintf(stderr, "sig_off (count = %i) at %s:%i\n",
                (int)cysigs.sig_on_count, file, line);
        fflush(stderr);
    }
#endif
    if (unlikely(cysigs.sig_on_count <= 0))
    {
        _sig_off_warning(file, line);
    }
    else
    {
        --cysigs.sig_on_count;
    }
}


/**********************************************************************
 * USER MACROS/FUNCTIONS                                              *
 **********************************************************************/

/* The actual macros which should be used in a program. */
#define sig_on()           _sig_on_(NULL)
#define sig_str(message)   _sig_on_(message)
#define sig_off()          _sig_off_(__FILE__, __LINE__)

/* sig_check() should be functionally equivalent to sig_on(); sig_off();
 * but much faster.  Essentially, it checks whether we missed any
 * interrupts.
 *
 * OUTPUT: zero if an interrupt occurred, non-zero otherwise.
 */
static inline int sig_check(void)
{
    if (unlikely(cysigs.interrupt_received) && cysigs.sig_on_count == 0)
    {
        _sig_on_interrupt_received();
        return 0;
    }

    return 1;
}


/*
 * Temporarily block interrupts from happening inside sig_on().  This
 * is meant to wrap malloc() for example.  sig_unblock() checks whether
 * an interrupt happened in the mean time.  If yes, the interrupt is
 * re-raised.
 *
 * NOTES:
 * - This only works inside sig_on()/sig_off().  Outside of sig_on(),
 *   interrupts behave as usual.  This is because we can't propagate
 *   Python exceptions from low-level C code.
 * - Despite the above note, it is still legal to use sig_block()
 *   outside of sig_on().
 * - Other signals still go through, because we can't really ignore
 *   SIGSEGV for example.
 * - It is NOT allowed to have an outer call of sig_on() inside
 *   sig_block().
 *   A deeper nesting (sig_on(); sig_block(); sig_on();) is OK.
 */
static inline void sig_block(void)
{
    /* This increment may not be atomic. However, that's not an issue
     * because our signal handlers do not change this value. The value
     * of block_sigint is set to 0 in _sig_on_recover, but that only
     * happens after a longjmp(). */
    ++cysigs.block_sigint;
}

static inline void sig_unblock(void)
{
#if ENABLE_DEBUG_CYSIGNALS
    if (cysigs.block_sigint < 1)
    {
        fprintf(stderr, "\n*** ERROR *** sig_unblock() with sig_on_count = %i, block_sigint = %i\n",
                (int)cysigs.sig_on_count, (int)cysigs.block_sigint);
        print_backtrace();
    }
#endif
    --cysigs.block_sigint;

    if (unlikely(cysigs.interrupt_received))
        /* Re-raise the signal if we can handle it now */
        if (cysigs.sig_on_count > 0 && cysigs.block_sigint == 0)
            proc_raise(cysigs.interrupt_received);
}


/*
 * Retry a failed computation starting from sig_on().
 */
static inline void sig_retry(void)
{
    /* If we're outside of sig_on(), we can't jump, so we can only bail
     * out */
    if (unlikely(cysigs.sig_on_count <= 0))
    {
        fprintf(stderr, "sig_retry() without sig_on()\n");
        proc_raise(SIGABRT);
    }
    cylongjmp(cysigs.env, -1);
}

/* Used in error callbacks from C code (in particular NTL and PARI).
 * This should be used after an exception has been raised to jump back
 * to sig_on() where the exception will be seen. */
static inline void sig_error(void)
{
    if (unlikely(cysigs.sig_on_count <= 0))
    {
        fprintf(stderr, "sig_error() without sig_on()\n");
    }
    proc_raise(SIGABRT);
}


static inline int _set_debug_level(int level)
{
#if ENABLE_DEBUG_CYSIGNALS
    int old = cysigs.debug_level;
    cysigs.debug_level = level;
    return old;
#else
    if (level == 0)
        return 0;    /* 0 is the only valid debug level */
    else
        return -1;   /* Error */
#endif
}

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* ifndef CYSIGNALS_MACROS_H */
