/*****************************************************************************
 *       Copyright (C) 2006 William Stein <wstein@gmail.com>
 *                     2006 Martin Albrecht <martinralbrecht+cysignals@gmail.com>
 *                     2010-2016 Jeroen Demeyer <jdemeyer@cage.ugent.be>
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


#include <setjmp.h>
#include <signal.h>
#include "debug.h"


/* Declare likely() and unlikely() as in Cython */
/* Test for GCC > 2.95 */
#if defined(__GNUC__)     && (__GNUC__ > 2 || (__GNUC__ == 2 && (__GNUC_MINOR__ > 95)))
  #define likely(x)   __builtin_expect(!!(x), 1)
  #define unlikely(x) __builtin_expect(!!(x), 0)
#else /* !__GNUC__ or GCC < 2.95 */
  #define likely(x)   (x)
  #define unlikely(x) (x)
#endif /* __GNUC__ */


#ifdef __cplusplus
extern "C" {
#endif

/* All the state of the signal handler is in this struct. */
typedef struct
{
    /* Reference counter for sig_on().
     * If this is strictly positive, we are inside a sig_on(). */
    volatile sig_atomic_t sig_on_count;

    /* If this is nonzero, it is a signal number of a non-critical
     * signal (e.g. SIGINT) which happened during a time when it could
     * not be handled.  This may be set when an interrupt occurs either
     * outside of sig_on() or inside sig_block().  To avoid race
     * conditions, this value may only be changed when all
     * interrupt-like signals are masked. */
    volatile sig_atomic_t interrupt_received;

    /* Are we currently handling a signal inside cysigs_signal_handler()?
     * This is set to 1 on entry in cysigs_signal_handler (not in
     * cysigs_interrupt_handler) and 0 in _sig_on_postjmp.  This is
     * needed to check for signals raised within the signal handler. */
    volatile sig_atomic_t inside_signal_handler;

    /* Non-zero if we currently are in a function such as malloc()
     * which blocks interrupts, zero normally.
     * See sig_block(), sig_unblock(). */
    volatile sig_atomic_t block_sigint;

    /* A jump buffer holding where to siglongjmp() after a signal has
     * been received. This is set by sig_on(). */
    sigjmp_buf env;

    /* An optional string may be passed to the signal handler which
     * will be used as the text for the exception. This can be set
     * using sig_str() instead of sig_on().
     */
    const char* s;

#if ENABLE_DEBUG_CYSIGNALS
    int debug_level;
#endif
} cysigs_t;

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* ifndef CYSIGNALS_STRUCT_SIGNALS_H */
