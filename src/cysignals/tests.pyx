"""
Test interrupt and signal handling

TESTS:

We disable crash logs for this test run::

    >>> import os
    >>> os.environ["CYSIGNALS_CRASH_LOGS"] = ""

"""

#*****************************************************************************
#       Copyright (C) 2010-2016 Jeroen Demeyer <jdemeyer@cage.ugent.be>
#
#  cysignals is free software: you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published
#  by the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  cysignals is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with cysignals.  If not, see <http://www.gnu.org/licenses/>.
#
#*****************************************************************************


from libc.signal cimport (SIGHUP, SIGINT, SIGABRT, SIGILL, SIGSEGV,
        SIGFPE, SIGBUS, SIGQUIT)
from libc.stdlib cimport abort

from cpython cimport PyErr_SetString

from .signals cimport *
from .memory cimport *

cdef extern from 'tests_helper.c':
    void ms_sleep(long ms) nogil
    void signal_after_delay(int signum, long ms) nogil
    void signals_after_delay(int signum, long ms, long interval, int n) nogil

cdef extern from *:
    ctypedef int volatile_int "volatile int"

# Default delay in milliseconds before raising signals
cdef long DEFAULT_DELAY = 200


########################################################################
# Disable debugging while testing                                      #
########################################################################

from .signals import set_debug_level
set_debug_level(0)


########################################################################
# C helper functions                                                   #
########################################################################
cdef void infinite_loop() nogil:
    while True:
        pass

cdef void infinite_malloc_loop() nogil:
    cdef size_t s = 1
    while True:
        sig_free(sig_malloc(s))
        s *= 2
        if (s > 1000000): s = 1

# Dereference a NULL pointer on purpose. This signals a SIGSEGV on most
# systems, but on older Mac OS X and possibly other systems, this
# signals a SIGBUS instead. In any case, this should give some signal.
cdef void dereference_null_pointer() nogil:
    cdef long* ptr = <long*>(0)
    ptr[0] += 1


########################################################################
# Python helper functions                                              #
########################################################################
class return_exception:
    """
    Decorator class which makes a function *return* an exception which
    is raised, to simplify doctests raising exceptions.

    EXAMPLES::

        >>> from cysignals.tests import return_exception
        >>> @return_exception
        ... def raise_interrupt():
        ...     raise KeyboardInterrupt("just testing")
        >>> raise_interrupt()
        KeyboardInterrupt('just testing',)

    """
    def __init__ (self, func):
        self.func = func
    def __call__ (self, *args):
        try:
            return self.func(*args)
        except BaseException as e:
            return e

def interrupt_after_delay(ms_delay=500):
    """
    Send an interrupt signal (``SIGINT``) to the process after a delay of
    ``ms_delay`` milliseconds.

    INPUT:

        - ``ms_delay`` -- (default: 500) a nonnegative integer indicating how
          many milliseconds to wait before raising the interrupt signal.

    EXAMPLES:

    This function is meant to test interrupt functionality.  We demonstrate here
    how to test that an infinite loop can be interrupted::

        >>> import cysignals.tests
        >>> try:
        ...     cysignals.tests.interrupt_after_delay()
        ...     while True:
        ...         pass
        ... except KeyboardInterrupt:
        ...     print("Caught KeyboardInterrupt")
        Caught KeyboardInterrupt

    """
    signal_after_delay(SIGINT, ms_delay)


def _sig_on():
    """
    A single ``sig_on()`` for doctesting purposes. This can never work
    for real code.
    """
    sig_on()


########################################################################
# Test basic interrupt-handling macros.                                #
# Since these are supposed to work without the GIL, we do all tests    #
# (if possible) within a "with nogil" block.                           #
########################################################################
def test_sig_off():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_off()

    """
    with nogil:
        sig_on()
        sig_off()

@return_exception
def test_sig_on(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on()
        KeyboardInterrupt()

    """
    with nogil:
        signal_after_delay(SIGINT, delay)
        sig_on()
        infinite_loop()

def test_sig_str(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_str()
        Traceback (most recent call last):
        ...
        RuntimeError: Everything ok!

    """
    with nogil:
        sig_str("Everything ok!")
        signal_after_delay(SIGABRT, delay)
        infinite_loop()

cdef c_test_sig_on_cython():
    sig_on()
    infinite_loop()

@return_exception
def test_sig_on_cython(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on_cython()
        KeyboardInterrupt()

    """
    signal_after_delay(SIGINT, delay)
    c_test_sig_on_cython()

cdef int c_test_sig_on_cython_except() nogil except 42:
    sig_on()
    infinite_loop()

@return_exception
def test_sig_on_cython_except(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on_cython_except()
        KeyboardInterrupt()

    """
    with nogil:
        signal_after_delay(SIGINT, delay)
        c_test_sig_on_cython_except()

cdef void c_test_sig_on_cython_except_all() nogil except *:
    sig_on()
    infinite_loop()

@return_exception
def test_sig_on_cython_except_all(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on_cython_except_all()
        KeyboardInterrupt()

    """
    with nogil:
        signal_after_delay(SIGINT, delay)
        c_test_sig_on_cython_except_all()

@return_exception
def test_sig_check(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_check()
        KeyboardInterrupt()

    """
    signal_after_delay(SIGINT, delay)
    while True:
        with nogil:
            sig_check()

@return_exception
def test_sig_check_inside_sig_on(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_check_inside_sig_on()
        KeyboardInterrupt()

    """
    with nogil:
        signal_after_delay(SIGINT, delay)
        sig_on()
        while True:
            sig_check()


########################################################################
# Test sig_retry() and sig_error()                                     #
########################################################################
def test_sig_retry():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_retry()
        10

    """
    cdef volatile_int v = 0

    with nogil:
        sig_on()
        if v < 10:
            v = v + 1
            sig_retry()
        sig_off()
    return v

@return_exception
def test_sig_retry_and_signal(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_retry_and_signal()
        KeyboardInterrupt()

    """
    cdef volatile_int v = 0

    with nogil:
        sig_on()
        if v < 10:
            v = v + 1
            sig_retry()
        signal_after_delay(SIGINT, delay)
        infinite_loop()

@return_exception
def test_sig_error():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_error()
        ValueError('some error',)

    """
    sig_on()
    PyErr_SetString(ValueError, "some error")
    sig_error()


########################################################################
# Test no_except macros                                                #
########################################################################
def test_sig_on_no_except(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on_no_except()
        42

    """
    if not sig_on_no_except():
        # We should never get here, because this sig_on_no_except()
        # will not catch a signals.
        print("Unexpected zero returned from sig_on_no_except()")
    sig_off()

    signal_after_delay(SIGINT, delay)
    if not sig_on_no_except():
        # We get here when we caught a signal.  An exception
        # has been raised, but Cython doesn't realize it yet.
        try:
            # Make Cython realize that there is an exception.
            # To Cython, it will look like the exception was raised on
            # the following line, so the try/except should work.
            cython_check_exception()
        except KeyboardInterrupt:
            return 42
        return 0 # fail
    infinite_loop()

def test_sig_str_no_except(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_str_no_except()
        Traceback (most recent call last):
        ...
        RuntimeError: Everything ok!

    """
    if not sig_on_no_except():
        # We should never get here, because this sig_on_no_except()
        # will not catch a signal.
        print("Unexpected zero returned from sig_on_no_except()")
    sig_off()

    if not sig_str_no_except("Everything ok!"):
        cython_check_exception()
        return 0 # fail
    signal_after_delay(SIGABRT, delay)
    infinite_loop()

@return_exception
def test_sig_check_no_except(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_check_no_except()
        KeyboardInterrupt()

    """
    with nogil:
        signal_after_delay(SIGINT, delay)
        while True:
            if not sig_check_no_except():
                cython_check_exception()
                break # fail


########################################################################
# Test different signals                                               #
########################################################################
def test_signal_segv(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_signal_segv()
        Traceback (most recent call last):
        ...
        SignalError: Segmentation fault

    """
    with nogil:
        sig_on()
        signal_after_delay(SIGSEGV, delay)
        infinite_loop()

def test_signal_fpe(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_signal_fpe()
        Traceback (most recent call last):
        ...
        FloatingPointError: Floating point exception

    """
    with nogil:
        sig_on()
        signal_after_delay(SIGFPE, delay)
        infinite_loop()

def test_signal_ill(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_signal_ill()
        Traceback (most recent call last):
        ...
        SignalError: Illegal instruction

    """
    with nogil:
        sig_on()
        signal_after_delay(SIGILL, delay)
        infinite_loop()

def test_signal_abrt(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_signal_abrt()
        Traceback (most recent call last):
        ...
        RuntimeError: Aborted

    """
    with nogil:
        sig_on()
        signal_after_delay(SIGABRT, delay)
        infinite_loop()

def test_signal_bus(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_signal_bus()
        Traceback (most recent call last):
        ...
        SignalError: Bus error

    """
    with nogil:
        sig_on()
        signal_after_delay(SIGBUS, delay)
        infinite_loop()

def test_signal_quit(long delay=DEFAULT_DELAY):
    """
    TESTS:

    We run Python in a subprocess and make it raise a SIGQUIT under
    ``sig_on()``.  This should cause Python to exit::

        >>> from subprocess import *
        >>> cmd = 'from cysignals.tests import *; test_signal_quit()'
        >>> print(Popen(['python', '-c', cmd], stdout=PIPE, stderr=PIPE).communicate()[1].decode("utf-8"))
        ------------------------------------------------------------------------
        ...
        ------------------------------------------------------------------------
        <BLANKLINE>

    """
    # The sig_on() shouldn't make a difference for SIGQUIT
    with nogil:
        sig_on()
        signal_after_delay(SIGQUIT, delay)
        infinite_loop()


########################################################################
# Test with "true" errors (not signals raised by hand)                 #
########################################################################
def test_dereference_null_pointer():
    """
    TESTS:

    This test should result in either a Segmentation Fault or a Bus
    Error. ::

        >>> from cysignals.tests import *
        >>> test_dereference_null_pointer()
        Traceback (most recent call last):
        ...
        SignalError: ...

    """
    with nogil:
        sig_on()
        dereference_null_pointer()

def unguarded_dereference_null_pointer():
    """
    TESTS:

    We run Python in a subprocess and dereference a NULL pointer without
    using ``sig_on()``. This will crash Python::

        >>> from subprocess import *
        >>> cmd = 'from cysignals.tests import *; unguarded_dereference_null_pointer()'
        >>> print(Popen(['python', '-c', cmd], stdout=PIPE, stderr=PIPE).communicate()[1].decode("utf-8"))
        ------------------------------------------------------------------------
        ...
        ------------------------------------------------------------------------
        Unhandled SIG...
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------
        <BLANKLINE>

    """
    with nogil:
        dereference_null_pointer()

def test_abort():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_abort()
        Traceback (most recent call last):
        ...
        RuntimeError: Aborted

    """
    with nogil:
        sig_on()
        abort()

def unguarded_abort():
    """
    TESTS:

    We run Python in a subprocess and make it call abort()::

        >>> from subprocess import *
        >>> cmd = 'from cysignals.tests import *; unguarded_abort()'
        >>> print(Popen(['python', '-c', cmd], stdout=PIPE, stderr=PIPE).communicate()[1].decode("utf-8"))
        ------------------------------------------------------------------------
        ...
        ------------------------------------------------------------------------
        Unhandled SIGABRT: An abort() occurred.
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------
        <BLANKLINE>

    """
    with nogil:
        abort()

def test_bad_str(long delay=DEFAULT_DELAY):
    """
    TESTS:

    We run Python in a subprocess and induce an error during the signal handler::

        >>> from subprocess import *
        >>> cmd = 'from cysignals.tests import *; test_bad_str()'
        >>> print(Popen(['python', '-c', cmd], stdout=PIPE, stderr=PIPE).communicate()[1].decode("utf-8"))
        ------------------------------------------------------------------------
        ...
        ------------------------------------------------------------------------
        An error occurred during signal handling.
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------
        <BLANKLINE>

    """
    cdef char* s = <char*>(16)
    with nogil:
        sig_str(s)
        signal_after_delay(SIGILL, delay)
        infinite_loop()


########################################################################
# Test various usage scenarios for sig_on()/sig_off()                  #
########################################################################
@return_exception
def test_sig_on_cython_after_delay(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on_cython_after_delay()
        KeyboardInterrupt()

    """
    with nogil:
        signal_after_delay(SIGINT, delay)
        ms_sleep(delay * 2)  # We get signaled during this sleep
        sig_on()             # The signal should be detected here
        abort()              # This should not be reached

def test_sig_on_inside_try(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_on_inside_try()

    """
    try:
        with nogil:
            sig_on()
            signal_after_delay(SIGABRT, delay)
            infinite_loop()
    except RuntimeError:
        pass

def test_interrupt_bomb(int n = 100, int p = 10):
    """
    Have `p` processes each sending `n` interrupts in very quick
    succession and see what happens :-)

    TESTS::

        >>> from cysignals.tests import *
        >>> test_interrupt_bomb()
        Received ... interrupts

    """
    cdef int i

    # Spawn p processes, each sending n signals with an interval of 1 millisecond
    cdef long base_delay=DEFAULT_DELAY + 5*p
    for i in range(p):
        signals_after_delay(SIGINT, base_delay, 1, n)

    # Some time later (after the smoke clears up) send a SIGABRT,
    # which will raise RuntimeError.
    signal_after_delay(SIGABRT, base_delay + 10*n + 1000)
    i = 0
    while True:
        try:
            with nogil:
                sig_on()
                infinite_loop()
        except KeyboardInterrupt:
            i = i + 1
        except RuntimeError:
            break
    print("Received %i/%i interrupts"%(i,n*p))

# Special thanks to Robert Bradshaw for suggesting the try/finally
# construction. -- Jeroen Demeyer
def test_try_finally_signal(long delay=DEFAULT_DELAY):
    """
    Test a try/finally construct for sig_on() and sig_off(), raising
    a signal inside the ``try``.

    TESTS::

        >>> from cysignals.tests import *
        >>> test_try_finally_signal()
        Traceback (most recent call last):
        ...
        RuntimeError: Aborted

    """
    sig_on()
    try:
        signal_after_delay(SIGABRT, delay)
        infinite_loop()
    finally:
        sig_off()

def test_try_finally_raise():
    """
    Test a try/finally construct for sig_on() and sig_off(), raising
    a Python exception inside the ``try``.

    TESTS::

        >>> from cysignals.tests import *
        >>> test_try_finally_raise()
        Traceback (most recent call last):
        ...
        RuntimeError: Everything ok!

    """
    sig_on()
    try:
        raise RuntimeError, "Everything ok!"
    finally:
        sig_off()

def test_try_finally_return():
    """
    Test a try/finally construct for sig_on() and sig_off(), doing a
    normal ``return`` inside the ``try``.

    TESTS::

        >>> from cysignals.tests import *
        >>> test_try_finally_return()
        'Everything ok!'

    """
    sig_on()
    try:
        return "Everything ok!"
    finally:
        sig_off()


########################################################################
# Test sig_block()/sig_unblock()                                       #
########################################################################
def test_sig_block(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_block()
        42

    """
    cdef volatile_int v = 0

    try:
        with nogil:
            sig_on()
            sig_block()
            signal_after_delay(SIGINT, delay)
            ms_sleep(delay * 2)  # We get signaled during this sleep
            v = 42
            sig_unblock()        # Here, the interrupt will be handled
            sig_off()
    except KeyboardInterrupt:
        return v

    # Never reached
    return 1

def test_sig_block_outside_sig_on(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_block_outside_sig_on()
        'Success'

    """
    with nogil:
        signal_after_delay(SIGINT, delay)

        # sig_block()/sig_unblock() shouldn't do anything
        # since we're outside of sig_on()
        sig_block()
        ms_sleep(delay * 2)  # We get signaled during this sleep
        sig_unblock()

    try:
        sig_on()  # Interrupt caught here
    except KeyboardInterrupt:
        return "Success"
    abort()   # This should not be reached

def test_signal_during_malloc(long delay=DEFAULT_DELAY):
    """
    Test a signal arriving during a sig_malloc() or sig_free() call.
    Since these are wrapped with sig_block()/sig_unblock(), we should
    safely be able to interrupt them.

    TESTS::

        >>> from cysignals.tests import *
        >>> for i in range(5):  # Several times to reduce chances of false positive
        ...     test_signal_during_malloc()

    """
    try:
        with nogil:
            signal_after_delay(SIGINT, delay)
            sig_on()
            infinite_malloc_loop()
    except KeyboardInterrupt:
        pass


########################################################################
# Benchmarking functions                                               #
########################################################################
def sig_on_bench():
    """
    Call ``sig_on()`` and ``sig_off()`` 1 million times.

    TESTS::

        >>> from cysignals.tests import *
        >>> sig_on_bench()

    """
    cdef int i
    with nogil:
        for i in range(1000000):
            sig_on()
            sig_off()

def sig_check_bench():
    """
    Call ``sig_check()`` 1 million times.

    TESTS::

        >>> from cysignals.tests import *
        >>> sig_check_bench()

    """
    cdef int i
    with nogil:
        for i in range(1000000):
            sig_check()


########################################################################
# Test SIGHUP                                                          #
########################################################################
@return_exception
def test_sighup(long delay=DEFAULT_DELAY):
    """
    Test a basic SIGHUP signal, which would normally exit the Python interpreter
    by raising ``SystemExit``.

    TESTS::

        >>> from cysignals.tests import *
        >>> test_sighup()
        SystemExit()

    """
    with nogil:
        signal_after_delay(SIGHUP, delay)
        while True:
            sig_check()

@return_exception
def test_sighup_and_sigint(long delay=DEFAULT_DELAY):
    """
    Test a SIGHUP and a SIGINT arriving at essentially the same time.
    The SIGINT should be ignored and we should get a ``SystemExit``.

    TESTS::

        >>> from cysignals.tests import *
        >>> test_sighup_and_sigint()
        SystemExit()

    """
    with nogil:
        sig_on()
        sig_block()
        signal_after_delay(SIGHUP, delay)
        signal_after_delay(SIGINT, delay)
        # 3 sleeps to ensure both signals arrive
        ms_sleep(delay)
        ms_sleep(delay)
        ms_sleep(delay)
        sig_unblock()
        sig_off()

def test_graceful_exit():
    r"""
    Start a subprocess, set up some ``atexit`` handler and kill the
    process with ``SIGHUP``. Then the process should exit gracefully,
    running the ``atexit`` handler::

        >>> from subprocess import *
        >>> A = Popen(['python'], stdin=PIPE, stdout=PIPE, stderr=PIPE)
        >>> _ = A.stdin.write(b'from cysignals.tests import test_graceful_exit\n')
        >>> _ = A.stdin.write(b'test_graceful_exit()\n')
        >>> A.stdin.close()

    Now read from the child until we read ``"GO"``.  This ensures that
    the child process has properly started before we kill it::

        >>> while b'GO' not in A.stdout.readline(): pass
        >>> import os, signal, sys
        >>> os.kill(A.pid, signal.SIGHUP)
        >>> _ = sys.stdout.write(A.stdout.read().decode("utf-8"))
        Goodbye!
        >>> A.wait()
        0

    """
    # This code is executed in the subprocess
    import atexit, sys
    def goodbye():
        print("Goodbye!")
    atexit.register(goodbye)

    # Print something to synchronize with the parent
    print("GO")
    sys.stdout.flush()

    # Wait to be killed...
    sig_on()
    infinite_loop()
