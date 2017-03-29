/*
 * C functions for use in tests.pyx
 */

/*****************************************************************************
 *       Copyright (C) 2010-2016 Jeroen Demeyer <jdemeyer@cage.ugent.be>
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

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/time.h>
#include <unistd.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/wait.h>


/* Wait ``ms`` milliseconds */
void ms_sleep(long ms)
{
    struct timeval t;
    t.tv_sec = (ms / 1000);
    t.tv_usec = (ms % 1000) * 1000;
    select(0, NULL, NULL, NULL, &t);
}


/* Signal process ``killpid`` with signal ``signum`` after ``ms``
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
void signal_pid_after_delay(int signum, pid_t killpid, long ms, long interval, int n)
{
    /* Flush all buffers before forking (otherwise we end up with two
     * copies of each buffer). */
    fflush(stdout);
    fflush(stderr);

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
}

/* Signal the Python process */
#define signal_after_delay(signum, ms) signal_pid_after_delay(signum, getpid(), ms, 0, 1)

/* The same as above, but sending ``n`` signals */
#define signals_after_delay(signum, ms, interval, n) signal_pid_after_delay(signum, getpid(), ms, interval, n)
