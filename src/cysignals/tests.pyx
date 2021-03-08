# cython: preliminary_late_includes_cy28=True
"""
Test interrupt and signal handling

TESTS:

We disable crash debugging for this test run::

    >>> import os
    >>> os.environ["CYSIGNALS_CRASH_NDEBUG"] = ""

Verify that the doctester was set up correctly::

    >>> import os
    >>> os.name == "posix"  # doctest: +SKIP_POSIX
    False
    >>> os.name == "nt"     # doctest: +SKIP_WINDOWS
    False

"""

#*****************************************************************************
#       Copyright (C) 2010-2016 Jeroen Demeyer <J.Demeyer@UGent.be>
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

from __future__ import absolute_import

from libc.signal cimport (SIGHUP, SIGINT, SIGABRT, SIGILL, SIGSEGV,
        SIGFPE, SIGBUS, SIGQUIT)
from libc.stdlib cimport abort
from libc.errno cimport errno
from posix.signal cimport sigaltstack, stack_t, SS_ONSTACK

from cpython cimport PyErr_SetString

from .signals cimport *
from .memory cimport *

cdef extern from "tests_helper.c" nogil:
    bint on_alt_stack()
    void ms_sleep(long ms)
    void signal_after_delay(int signum, long ms)
    void signals_after_delay(int signum, long ms, long interval, int n)
    void* map_noreserve()
    int unmap_noreserve(void* addr)


cdef extern from "<pthread.h>" nogil:
    ctypedef unsigned long pthread_t
    ctypedef struct pthread_attr_t:
        pass
    int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                       void *(*start_routine) (void *), void *arg)
    int pthread_join(pthread_t thread, void **retval)


cdef extern from *:
    ctypedef int volatile_int "volatile int"


# Default delay in milliseconds before raising signals
cdef long DEFAULT_DELAY = 200


import sys
from subprocess import Popen, PIPE


########################################################################
# Disable debugging while testing                                      #
########################################################################

from .signals import set_debug_level
set_debug_level(0)


########################################################################
# C helper functions                                                   #
########################################################################
cdef void infinite_loop() nogil:
    # Ensure that the compiler cannot "optimize away" this infinite
    # loop, see https://bugs.llvm.org/show_bug.cgi?id=965
    cdef volatile_int x = 0
    while x == 0:
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
    cdef volatile_int* ptr = <volatile_int*>(0)
    ptr[0] += 1


cdef int stack_overflow(volatile_int* x=NULL) nogil:
    cdef volatile_int a = 0
    if x is not NULL:
        a = x[0]
    a += stack_overflow(&a)
    a += stack_overflow(&a)
    return a


########################################################################
# Python helper functions                                              #
########################################################################

class return_exception(object):
    """
    Decorator class which makes a function *return* an exception which
    is raised, to simplify doctests raising exceptions.

    EXAMPLES::

        >>> from cysignals.tests import return_exception
        >>> @return_exception
        ... def raise_interrupt():
        ...     raise KeyboardInterrupt("just", "testing")
        >>> raise_interrupt()
        KeyboardInterrupt('just', 'testing')

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


def on_stack():
    """
    Are we currently on the alternate signal stack (see sigaltstack(2))?

    EXAMPLES::

        >>> from cysignals.tests import on_stack
        >>> on_stack()
        False

    """
    return on_alt_stack()


def _sig_on():
    """
    A single ``sig_on()`` for doctesting purposes. This can never work
    for real code.
    """
    sig_on()


def subpython_err(command, **kwds):
    """
    Run ``command`` in a Python subprocess and print the standard error
    which was generated.
    """
    argv = [sys.executable, '-c', command]
    P = Popen(argv, stdout=PIPE, stderr=PIPE, universal_newlines=True, **kwds)
    (out, err) = P.communicate()
    sys.stdout.write(err)


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
        sig_on()
        signal_after_delay(SIGINT, delay)
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

def test_sig_error():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_error()
        Traceback (most recent call last):
        ...
        ValueError: some error

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
        # will not catch any signal.
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

        >>> from cysignals.tests import subpython_err
        >>> subpython_err('from cysignals.tests import *; test_signal_quit()')
        ---------------------------------------------------------------------...

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
        >>> on_stack()
        False

    """
    with nogil:
        sig_on()
        dereference_null_pointer()

def unguarded_dereference_null_pointer():
    """
    TESTS:

    We run Python in a subprocess and dereference a NULL pointer without
    using ``sig_on()``. This will crash Python::

        >>> from cysignals.tests import subpython_err
        >>> subpython_err('from cysignals.tests import *; unguarded_dereference_null_pointer()')
        ---------------------------------------------------------------------...
        Unhandled SIG...
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------

    The same but with ``CYSIGNALS_CRASH_QUIET`` set. This will crash
    Python silently::

        >>> import os
        >>> env = dict(os.environ)
        >>> env["CYSIGNALS_CRASH_QUIET"] = ""
        >>> subpython_err('from cysignals.tests import *; unguarded_dereference_null_pointer()', env=env)

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

        >>> from cysignals.tests import subpython_err
        >>> subpython_err('from cysignals.tests import *; unguarded_abort()')
        ---------------------------------------------------------------------...
        Unhandled SIGABRT: An abort() occurred.
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------

    """
    with nogil:
        abort()


def test_stack_overflow():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_stack_overflow()
        Traceback (most recent call last):
        ...
        SignalError: Segmentation fault

    """
    with nogil:
        sig_on()
        stack_overflow()

def unguarded_stack_overflow():
    """
    TESTS:

    We run Python in a subprocess and overflow the stack::

        >>> from cysignals.tests import subpython_err
        >>> subpython_err('from cysignals.tests import *; unguarded_stack_overflow()')
        ---------------------------------------------------------------------...
        Unhandled SIGSEGV: A segmentation fault occurred.
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------

    """
    with nogil:
        stack_overflow()


def test_access_mmap_noreserve():
    """
    TESTS:

    Regression test for https://github.com/sagemath/cysignals/pull/108; if
    the issue is fixed then ``test_access_mmap_noreserve()`` should have no
    output.  Otherwise the subprocess will exit and report an error occurred
    during signal handling::

        >>> from cysignals.tests import test_access_mmap_noreserve
        >>> test_access_mmap_noreserve()

    """
    cdef int* ptr = <int*>map_noreserve()
    if ptr is NULL:
        raise RuntimeError(f"mmap() failed; errno: {errno}")

    ptr[0] += 1  # Should just work

    if unmap_noreserve(ptr) != 0:
        raise RuntimeError(f"munmap() failed; errno: {errno}")


def test_bad_str(long delay=DEFAULT_DELAY):
    """
    TESTS:

    We run Python in a subprocess and induce an error during the signal handler::

        >>> from cysignals.tests import subpython_err
        >>> subpython_err('from cysignals.tests import *; test_bad_str()')
        ---------------------------------------------------------------------...
        Unhandled SIGSEGV during signal handling.
        This probably occurred because a *compiled* module has a bug
        in it and is not properly wrapped with sig_on(), sig_off().
        Python will now terminate.
        ------------------------------------------------------------------------

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


def test_interrupt_bomb(long n=100, long p=10):
    """
    Have `p` processes each sending `n` interrupts in very quick
    succession and see what happens :-)

    TESTS::

        >>> from cysignals.tests import *
        >>> test_interrupt_bomb()  # doctest: +SKIP_CYGWIN
        Received ... interrupts

    """
    cdef long i

    # Spawn p processes, each sending n signals with an interval of 1 millisecond
    cdef long base_delay = DEFAULT_DELAY + 5*p
    for i in range(p):
        signals_after_delay(SIGINT, base_delay, 1, n)

    i = 0
    while True:
        try:
            with nogil:
                sig_on()
                ms_sleep(1000)
                sig_off()
            # If 1 second passed since the last interrupt, we assume that
            # no more interrupts are coming.
            if i > 0:
                break
        except KeyboardInterrupt:
            i += 1
    print(f"Received {i}/{n*p} interrupts")


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
# Test sig_occurred()                                                  #
########################################################################

def print_sig_occurred():
    """
    Print the exception which is currently being handled.

    Note that we print instead of return the exception to mess as little
    as possible with refcounts.

    EXAMPLES::

        >>> from cysignals.tests import *
        >>> print_sig_occurred()
        No current exception

    In Python 3 and in Cython, the exception remains alive only inside
    the ``except`` clause handling the exception. In Python 2, it stays
    alive as long as the stack frame where it was raised is still running
    and calling ``sys.exc_clear()`` clears it::

        >>> import sys
        >>> from cysignals.alarm import alarm
        >>> if hasattr(sys, "exc_clear"):
        ...     # Python 2
        ...     def testfunc():
        ...         try:
        ...             alarm(0.1)
        ...             while True:
        ...                pass
        ...         except KeyboardInterrupt:
        ...             pass
        ...         print_sig_occurred()
        ...         sys.exc_clear()
        ...         print_sig_occurred()
        ... else:
        ...     # Python 3
        ...     def testfunc():
        ...         try:
        ...             alarm(0.1)
        ...             while True:
        ...                pass
        ...         except KeyboardInterrupt:
        ...             print_sig_occurred()
        ...         print_sig_occurred()
        >>> testfunc()
        AlarmInterrupt
        No current exception

    """
    exc = sig_occurred()
    try:
        cython_check_exception()
    finally:
        if exc is NULL:
            print("No current exception")
        else:
            e = <object>exc
            t = str(e)
            if t:
                t = ": " + t
            print(type(e).__name__ + t)


def test_sig_occurred_finally():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_occurred_finally()
        No current exception
        RuntimeError: test_sig_occurred_finally()
        RuntimeError: test_sig_occurred_finally()
        No current exception

    """
    try:
        try:
            sig_str("test_sig_occurred_finally()")
        finally:
            print_sig_occurred()  # output 1 and 2
    except RuntimeError:
        print_sig_occurred()  # output 3
    else:
        abort()
    print_sig_occurred()  # output 4


def test_sig_occurred_live_exception():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> try:
        ...     test_sig_occurred_live_exception()
        ... except RuntimeError:
        ...     pass
        RuntimeError: Aborted
        >>> print_sig_occurred()
        No current exception

    """
    if not sig_on_no_except():
        print_sig_occurred()
    sig_error()


def test_sig_occurred_dealloc():
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> try:
        ...     test_sig_occurred_dealloc()
        ... except RuntimeError:
        ...     pass
        __dealloc__: RuntimeError: test_sig_occurred_dealloc()
        >>> print_sig_occurred()
        No current exception

    """
    x = DeallocDebug()
    sig_str("test_sig_occurred_dealloc()")
    abort()


def test_sig_occurred_dealloc_in_gc():
    """
    Regression test for https://github.com/sagemath/cysignals/issues/126

    TESTS:

    The first part of this is similar to ``test_sig_occurred_dealloc()`` but we
    keep a reference to the exception so it doesn't go away right away::

        >>> from cysignals.tests import *
        >>> import sys
        >>> e = None
        >>> try:
        ...     test_sig_occurred_dealloc_in_gc()
        ... except RuntimeError as exc:
        ...     e = exc
        >>> print_sig_occurred()
        RuntimeError: test_sig_occurred_dealloc_in_gc()

    Python 2 keeps the target of the "except as" in local scope, so make sure
    to delete it as well::

        >>> if sys.version_info[0] < 3: del exc

    Put the exception into a list containing a reference to itself, so that
    when the garbage collector runs (in ``verify_exc_value``) its reference
    count drops to 1.  Also include a ``DeallocDebug`` so that
    ``sig_occurred()`` is called during GC.

    We also temporarily disable automatic GC to ensure that the garbage
    collector is not called except by ``verify_exc_value()``::

        >>> import gc
        >>> l = [DeallocDebug(), e]
        >>> l.append(l)
        >>> gc.disable()
        >>> try:
        ...     del l, e
        ...     print_sig_occurred()
        ... finally:
        ...     gc.enable()
        __dealloc__: No current exception
        No current exception

    """
    sig_str("test_sig_occurred_dealloc_in_gc()")
    abort()


cdef class DeallocDebug:
    def __dealloc__(self):
        sys.stdout.write("__dealloc__: ")
        print_sig_occurred()


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

def test_sig_block_nested(long delay=DEFAULT_DELAY):
    """
    TESTS::

        >>> from cysignals.tests import *
        >>> test_sig_block_nested()
        42

    """
    cdef volatile_int v = 0

    try:
        with nogil:
            sig_on()
            sig_block()
            sig_block()
            sig_block()
            signal_after_delay(SIGINT, delay)
            sig_unblock()
            ms_sleep(delay * 2)  # We get signaled during this sleep
            sig_check()
            sig_unblock()
            sig_on()
            sig_off()
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
        sig_block()
        ms_sleep(delay * 2)  # We get signaled during this sleep
        sig_unblock()
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

        >>> from sys import executable
        >>> from subprocess import *
        >>> A = Popen([executable], stdin=PIPE, stdout=PIPE, stderr=PIPE)
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


########################################################################
# Test thread safety                                                   #
########################################################################

def test_thread_sig_block(long delay=DEFAULT_DELAY):
    """
    Test that calling ``sig_block``/``sig_unblock`` is thread-safe.

    TESTS::

        >>> from cysignals.tests import *
        >>> test_thread_sig_block()

    """
    cdef pthread_t t1, t2
    with nogil:
        sig_on()
        if pthread_create(&t1, NULL, func_thread_sig_block, NULL):
            sig_error()
        if pthread_create(&t2, NULL, func_thread_sig_block, NULL):
            sig_error()
        if pthread_join(t1, NULL):
            sig_error()
        if pthread_join(t2, NULL):
            sig_error()
        sig_off()


cdef void* func_thread_sig_block(void* ignored) nogil:
    # This is executed by the two threads spawned by test_thread_sig_block()
    cdef int n
    for n in range(1000000):
        sig_block()
        if not (1 <= cysigs.block_sigint <= 2):
            sig_error()
        sig_unblock()
