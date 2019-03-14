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

#ifndef CYSIGNALS_STRUCT_SIGNALS_H
#define CYSIGNALS_STRUCT_SIGNALS_H


#include "cysignals_config.h"
#include <setjmp.h>
#include <signal.h>
#include <Python.h>


/* Choose sigjmp/longjmp variant */
#if CYSIGNALS_USE_SIGSETJMP
#define cyjmp_buf sigjmp_buf
#define cysetjmp(env) sigsetjmp(env, 0)
#define cylongjmp(env, val) siglongjmp(env, val)
#else
#define cyjmp_buf jmp_buf
#define cysetjmp(env) setjmp(env)
#define cylongjmp(env, val) longjmp(env, val)
#endif


/* Define a cy_atomic_int type for atomic operations */
#if CYSIGNALS_C_ATOMIC || CYSIGNALS_CXX_ATOMIC
typedef volatile _Atomic int cy_atomic_int;
#elif CYSIGNALS_STD_ATOMIC
#include <atomic>
typedef volatile std::atomic<int> cy_atomic_int;
#else
/* The type sig_atomic_t is not really atomic, but it's the best we have */
typedef volatile sig_atomic_t cy_atomic_int;
#endif


/* All the state of the signal handler is in this struct. */
typedef struct
{
    /* Reference counter for sig_on().
     * If this is strictly positive, we are inside a sig_on(). */
    cy_atomic_int sig_on_count;

    /* If this is nonzero, it is a signal number of a non-critical
     * signal (e.g. SIGINT) which happened during a time when it could
     * not be handled.  This may be set when an interrupt occurs either
     * outside of sig_on() or inside sig_block().  To avoid race
     * conditions, this value may only be changed when all
     * interrupt-like signals are masked. */
    cy_atomic_int interrupt_received;

    /* Are we currently handling a signal inside cysigs_signal_handler()?
     * This is set to 1 on entry in cysigs_signal_handler (not in
     * cysigs_interrupt_handler) and 0 in _sig_on_postjmp.  This is
     * needed to check for signals raised within the signal handler. */
    cy_atomic_int inside_signal_handler;

    /* Non-zero if we currently are in a function such as malloc()
     * which blocks interrupts, zero normally.
     * See sig_block(), sig_unblock(). */
    cy_atomic_int block_sigint;

    /* A jump buffer holding where to cylongjmp() after a signal has
     * been received. This is set by sig_on(). */
    cyjmp_buf env;

    /* An optional string (in UTF-8 encoding) to be used as text for
     * the exception raised by sig_raise_exception(). If this is NULL,
     * use some default string depending on the type of signal. This can
     * be set using sig_str() instead of sig_on(). */
    const char* s;

    /* Reference to the exception object that we raised (NULL if none).
     * This is used by the sig_occurred function. */
    PyObject* exc_value;

#if ENABLE_DEBUG_CYSIGNALS
    int debug_level;
#endif
} cysigs_t;

#endif  /* ifndef CYSIGNALS_STRUCT_SIGNALS_H */
