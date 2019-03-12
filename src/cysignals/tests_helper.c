/*
 * C functions for use in tests.pyx
 */

/*****************************************************************************
 *       Copyright (C) 2010-2016 Jeroen Demeyer <J.Demeyer@UGent.be>
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

#include "config.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#if HAVE_UNISTD_H
#include <unistd.h>
#endif
#if HAVE_SYS_MMAN_H
#include <sys/mman.h>
#endif
#if HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#if HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#if HAVE_SYS_WAIT_H
#include <sys/wait.h>
#endif
#if HAVE_WINDOWS_H
#include <windows.h>
#endif


static int on_alt_stack(void)
{
#if HAVE_SIGALTSTACK
    stack_t oss;
    sigaltstack(NULL, &oss);
    return oss.ss_flags & SS_ONSTACK;
#else
    return 0;
#endif
}


/* Wait ``ms`` milliseconds */
static void ms_sleep(long ms)
{
#if HAVE_UNISTD_H
    usleep(1000 * ms);
#else
    Sleep(ms);
#endif
}


/* Calls mmap if available with the MAP_NORESERVE flag (if this is not
 * supported, just use malloc). This is used currently just to test a
 * regression on Cygwin (see test_access_mmap_noreserve).
 */
#define MAP_NORESERVE_LEN (1 << 22)
#if defined(MAP_NORESERVE)
static void* map_noreserve(void)
{
    void* addr = mmap(NULL, MAP_NORESERVE_LEN, PROT_READ|PROT_WRITE,
                      MAP_ANON|MAP_PRIVATE|MAP_NORESERVE, -1, 0);
    if (addr == MAP_FAILED) return NULL;
    return addr;
}

static int unmap_noreserve(void* addr) {
    return munmap(addr, MAP_NORESERVE_LEN);
}
#else
static void* map_noreserve(void)
{
    return malloc(MAP_NORESERVE_LEN);
}

static int unmap_noreserve(void* addr) {
    free(addr);
    return 0;
}
#endif


/* Signal the running process with signal ``signum`` after ``ms``
 * milliseconds.  Wait ``interval`` milliseconds, then signal again.
 * Repeat this until ``n`` signals have been sent.
 *
 * This works as follows:
 *  - create a first child process in a new process group
 *  - the main process waits until the first child process terminates
 *  - this child process creates a second child process
 *  - the second child process kills the first child process
 *  - the main process sees that the first child process is killed
 *    and continues running Python code
 *  - the second child process does the actual waiting and signalling
 */
static void signals_after_delay(int signum, long ms, long interval, int n)
{
    /* Flush all buffers before forking (otherwise we end up with two
     * copies of each buffer). */
    fflush(stdout);
    fflush(stderr);

#if !HAVE_KILL
    /* On Windows, we just send the signal right away. This is because
     * there is no way to send a signal to an arbitrary process
     * (or thread). Raising the signal here decreases slightly the
     * usefulness of the tests, but it should work anyway. */
    raise(signum);
    return;
#else
    pid_t killpid = getpid();

    pid_t child1 = fork();
    if (child1 == -1) {perror("fork"); exit(1);}

    if (!child1)
    {
        /* This is child process 1 */
        child1 = getpid();

        /* New process group to prevent us getting the signals. */
        setpgid(0,0);

        /* Unblock SIGINT (to fix a warning when testing sig_block()) */
        cysigs.block_sigint = 0;

        /* Make sure SIGTERM simply terminates the process */
        signal(SIGTERM, SIG_DFL);

        pid_t child2 = fork();
        if (child2 == -1) exit(1);

        if (!child2)
        {
            /* This is child process 2 */
            kill(child1, SIGTERM);

            /* Signal Python after delay */
            ms_sleep(ms);
            for (;;)
            {
                kill(killpid, signum);
                if (--n == 0) exit(0);
                ms_sleep(interval);
            }
        }

        /* Wait to be killed by child process 2... */
        /* We use a 2-second timeout in case there is trouble. */
        ms_sleep(2000);
        exit(2);  /* This should NOT be reached */
    }

    /* Main Python process, continue when child 1 finishes */
    int wait_status;
    waitpid(child1, &wait_status, 0);
#endif
}

/* Send just one signal */
#define signal_after_delay(signum, ms) signals_after_delay(signum, ms, 0, 1)
