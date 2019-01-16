r"""
Python interface to signal handlers
===================================

In this module, we distinguish between the "OS-level" signal handler
and the "Python-level" signal handler.

The Python function :func:`signal.signal` sets both of these: it sets
the Python-level signal handler to the function specified by the user.
It also sets the OS-level signal handler to a specific C function
which calls the Python-level signal handler.

The Python ``signal`` module does not allow access to the OS-level
signal handler (in particular, it does not allow one to temporarily change
a signal handler if the OS-level handler was not the Python one).
"""

#*****************************************************************************
#       Copyright (C) 2017 Jeroen Demeyer <J.Demeyer@UGent.be>
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

import signal
from signal import getsignal
from libc.string cimport memcpy
from libc.signal cimport SIG_IGN, SIG_DFL, SIGKILL, SIGSTOP, SIGFPE
from posix.signal cimport *
from cpython.object cimport Py_EQ, Py_NE
from cpython.exc cimport PyErr_SetFromErrno, PyErr_CheckSignals


# Fix https://github.com/cython/cython/pull/2756
cdef extern from "<signal.h>" nogil:
    int sigismember(const sigset_t *, int)


cdef class SigAction:
    """
    An opaque object representing an OS-level signal handler.

    The only legal initializers are ``signal.SIG_DFL`` (the default),
    ``signal.SIG_IGN`` and another ``SigAction`` object
    (which is copied).

    EXAMPLES::

        >>> from cysignals.pysignals import SigAction
        >>> SigAction()
        <SigAction with sa_handler=SIG_DFL>
        >>> import signal
        >>> SigAction(signal.SIG_DFL)
        <SigAction with sa_handler=SIG_DFL>
        >>> SigAction(signal.SIG_IGN)
        <SigAction with sa_handler=SIG_IGN>
        >>> A = SigAction(signal.SIG_IGN)
        >>> SigAction(A)
        <SigAction with sa_handler=SIG_IGN>
        >>> SigAction(A) == A
        True

    TESTS::

        >>> SigAction(42)
        Traceback (most recent call last):
        ...
        TypeError: cannot initialize SigAction from <... 'int'>

    """
    def __cinit__(self, action=signal.SIG_DFL):
        sigemptyset(&self.act.sa_mask)
        self.act.sa_flags = 0
        if action is signal.SIG_DFL:
            self.act.sa_handler = SIG_DFL
        elif action is signal.SIG_IGN:
            self.act.sa_handler = SIG_IGN
        elif isinstance(action, SigAction):
            memcpy(&self.act, &(<SigAction>action).act, sizeof(self.act))
        else:
            raise TypeError(f"cannot initialize SigAction from {type(action)}")

    def __repr__(self):
        cdef object addr
        if self.act.sa_flags & SA_SIGINFO:
            addr = <size_t>(self.act.sa_sigaction)
            handler = f"sa_sigaction={addr:#x}"
        elif self.act.sa_handler is SIG_DFL:
            addr = <size_t>(self.act.sa_handler)
            handler = "sa_handler=SIG_DFL"
        elif self.act.sa_handler is SIG_IGN:
            addr = <size_t>(self.act.sa_handler)
            handler = "sa_handler=SIG_IGN"
        else:
            addr = <size_t>(self.act.sa_handler)
            handler = f"sa_handler={addr:#x}"
        return f"<SigAction with {handler}>"

    def __richcmp__(self, other, int op):
        """
        Compare two ``SigAction`` instances for equality, where two
        instances are considered equal if they have the same handler
        function and the same flags.

        EXAMPLES::

            >>> from cysignals.pysignals import SigAction
            >>> import signal
            >>> A = SigAction(signal.SIG_DFL)
            >>> B = SigAction(signal.SIG_DFL)
            >>> C = SigAction(signal.SIG_IGN)
            >>> A == B
            True
            >>> A == C
            False
            >>> A != B
            False
            >>> A != C
            True
            >>> A < A
            Traceback (most recent call last):
            ...
            TypeError: SigAction instances can only be compared with == or !=

        """
        cdef SigAction a, b
        try:
            a = <SigAction?>self
            b = <SigAction?>other
        except TypeError:
            return NotImplemented
        if op != Py_EQ and op != Py_NE:
            raise TypeError("SigAction instances can only be compared with == or !=")
        if a.act.sa_flags != b.act.sa_flags:
            return op == Py_NE
        cdef int equal
        if a.act.sa_flags & SA_SIGINFO:
            equal = (a.act.sa_sigaction == b.act.sa_sigaction)
        else:
            equal = (a.act.sa_handler == b.act.sa_handler)
        return equal == (op == Py_EQ)


def getossignal(int sig):
    r"""
    Get the OS-level signal handler.

    This returns an opaque object of type :class:`SigAction` which can
    only be used in a future call to :func:`setossignal`.

    EXAMPLES::

        >>> from cysignals.pysignals import getossignal
        >>> import signal
        >>> getossignal(signal.SIGINT)
        <SigAction with sa_handler=0x...>
        >>> getossignal(signal.SIGUSR1)
        <SigAction with sa_handler=SIG_DFL>
        >>> def handler(*args): pass
        >>> _ = signal.signal(signal.SIGUSR1, handler)
        >>> getossignal(signal.SIGUSR1)
        <SigAction with sa_handler=0x...>

    Check whether a signal is handled by the Python signal handler::

        >>> from cysignals.pysignals import python_os_handler
        >>> getossignal(signal.SIGUSR1) == python_os_handler
        True
        >>> _ = signal.signal(signal.SIGUSR1, signal.SIG_IGN)
        >>> getossignal(signal.SIGUSR1) == python_os_handler
        False
        >>> getossignal(signal.SIGABRT) == python_os_handler
        False

    TESTS::

        >>> getossignal(None)
        Traceback (most recent call last):
        ...
        TypeError: an integer is required
        >>> getossignal(-1)
        Traceback (most recent call last):
        ...
        OSError: [Errno 22] Invalid argument

    """
    cdef SigAction action = SigAction.__new__(SigAction)
    if sigaction(sig, NULL, &action.act): PyErr_SetFromErrno(OSError)
    return action


def setossignal(int sig, action):
    r"""
    Set the OS-level signal handler to ``action``, which should either
    be ``signal.SIG_DFL`` or ``signal.SIG_IGN`` or a :class:`SigAction`
    object returned by an earlier call to :func:`getossignal` or
    :func:`setossignal`.

    Return the old signal handler.

    EXAMPLES::

        >>> from cysignals.pysignals import setossignal
        >>> import os, signal
        >>> def handler(*args): print("got signal")
        >>> _ = signal.signal(signal.SIGHUP, handler)
        >>> os.kill(os.getpid(), signal.SIGHUP)
        got signal
        >>> pyhandler = setossignal(signal.SIGHUP, signal.SIG_IGN)
        >>> pyhandler
        <SigAction with sa_handler=0x...>
        >>> os.kill(os.getpid(), signal.SIGHUP)
        >>> setossignal(signal.SIGHUP, pyhandler)
        <SigAction with sa_handler=SIG_IGN>
        >>> os.kill(os.getpid(), signal.SIGHUP)
        got signal
        >>> setossignal(signal.SIGHUP, signal.SIG_DFL) == pyhandler
        True

    TESTS::

        >>> setossignal(signal.SIGHUP, None)
        Traceback (most recent call last):
        ...
        TypeError: cannot initialize SigAction from <... 'NoneType'>
        >>> setossignal(-1, signal.SIG_DFL)
        Traceback (most recent call last):
        ...
        OSError: [Errno 22] Invalid argument

    """
    cdef SigAction new
    if isinstance(action, SigAction):
        new = <SigAction>action
    else:
        new = SigAction(action)
    cdef SigAction old = SigAction.__new__(SigAction)
    if sigaction(sig, &new.act, &old.act): PyErr_SetFromErrno(OSError)
    return old


def setsignal(int sig, action, osaction=None):
    r"""
    Set the Python-level signal handler for signal ``sig`` to
    ``action``. If ``osaction`` is given, set the OS-level signal
    handler to ``osaction``. If ``osaction`` is ``None`` (the default),
    change only the Python-level handler and keep the OS-level handler.

    Return the old Python-level handler.

    EXAMPLES::

        >>> from cysignals.pysignals import *
        >>> def handler(*args): print("got signal")
        >>> _ = signal.signal(signal.SIGSEGV, handler)
        >>> A = getossignal(signal.SIGILL)
        >>> _ = setsignal(signal.SIGILL, getsignal(signal.SIGSEGV))
        >>> getossignal(signal.SIGILL) == A
        True
        >>> _ = setossignal(signal.SIGILL, getossignal(signal.SIGSEGV))
        >>> import os
        >>> os.kill(os.getpid(), signal.SIGILL)
        got signal
        >>> setsignal(signal.SIGILL, signal.SIG_DFL)
        <function handler at 0x...>
        >>> _ = setsignal(signal.SIGALRM, signal.SIG_DFL, signal.SIG_IGN)
        >>> os.kill(os.getpid(), signal.SIGALRM)
        >>> _ = setsignal(signal.SIGALRM, handler, getossignal(signal.SIGSEGV))
        >>> os.kill(os.getpid(), signal.SIGALRM)
        got signal

    TESTS::

        >>> setsignal(-1, signal.SIG_DFL)
        Traceback (most recent call last):
        ...
        OSError: [Errno 22] Invalid argument

    """
    # Since we don't have direct access to the Python-level handler,
    # we use signal.signal to set the Python-level and OS-level
    # handlers and then set the OS-level signal handler.
    # To avoid race conditions, we need to mask the signal during this
    # operation.
    cdef sigaction_t oldact
    cdef sigaction_t* actptr

    cdef sigset_t block, oldmask
    sigemptyset(&block)
    if sigaddset(&block, sig): PyErr_SetFromErrno(OSError)

    if sigprocmask(SIG_BLOCK, &block, &oldmask): PyErr_SetFromErrno(OSError)
    try:
        # Check for pending signal before changing signal handler
        # to work around https://bugs.python.org/issue30057
        PyErr_CheckSignals()
        # Determine new OS-level signal handler
        if osaction is None:  # Use the current handler
            if sigaction(sig, NULL, &oldact): PyErr_SetFromErrno(OSError)
            actptr = &oldact
        else:  # Use given handler
            if not isinstance(osaction, SigAction):
                osaction = SigAction(osaction)
            actptr = &(<SigAction>osaction).act
        old = signal.signal(sig, action)
        if sigaction(sig, actptr, NULL): PyErr_SetFromErrno(OSError)
    finally:
        if sigprocmask(SIG_SETMASK, &oldmask, NULL): PyErr_SetFromErrno(OSError)
    return old


cdef class changesignal:
    """
    Context to temporarily change a signal handler.

    This should be used as follows::

        with changesignal(sig, action):
            ...

    Inside the context, code behaves as if ``signal.signal(sig, action)``
    was called. When leaving the context, the signal handler is
    restored to what it was before. Both the Python-level and OS-level
    signal handlers are restored.

    EXAMPLES::

        >>> from cysignals.pysignals import changesignal
        >>> import os, signal
        >>> def handler(*args):
        ...     print("got signal")
        >>> _ = signal.signal(signal.SIGQUIT, signal.SIG_IGN)
        >>> with changesignal(signal.SIGQUIT, handler):
        ...     os.kill(os.getpid(), signal.SIGQUIT)
        got signal
        >>> os.kill(os.getpid(), signal.SIGQUIT)
        >>> with changesignal(signal.SIGQUIT, handler):
        ...     setossignal(signal.SIGQUIT, signal.SIG_DFL)
        ...     raise Exception("just testing")
        Traceback (most recent call last):
        ...
        Exception: just testing
        >>> os.kill(os.getpid(), signal.SIGQUIT)

    """
    cdef public int sig
    cdef public action, old, osold

    def __init__(self, sig, action):
        self.sig = sig
        self.action = action

    def __enter__(self):
        self.osold = getossignal(self.sig)
        self.old = signal.signal(self.sig, self.action)
        return self

    def __exit__(self, *args):
        setsignal(self.sig, self.old, self.osold)


cdef class containsignals:
    """
    Context to revert any changes to given signal handlers and block
    those signals.

    This should be used as follows::

        with containsignals(signals):
            ...

    where ``signals`` is a list of signals (by default, all signals
    numbered from 1 to 31 except for ``SIGKILL`` and ``SIGSTOP``,
    which cannot be handled).

    When entering the context, the current handlers of those signals are
    saved. They are restored when exiting the context. This is mainly
    meant to prevent unwanted changes to signal handlers that other code
    may make. Both the Python-level and OS-level signal handlers are
    saved and restored.

    Also, the signals from the list ``signals`` are blocked. So any
    newly-installed signal handlers are prevented from being triggered.

    EXAMPLES::

        >>> from cysignals.pysignals import containsignals
        >>> import os, signal
        >>> def handler(*args):
        ...     print("got signal")
        >>> _ = signal.signal(signal.SIGBUS, handler)
        >>> with containsignals([signal.SIGBUS]):
        ...     _ = signal.signal(signal.SIGBUS, signal.SIG_DFL)
        ...     # This signal is delivered when exiting the context
        ...     os.kill(os.getpid(), signal.SIGBUS)
        ...     print("no signal yet")
        no signal yet
        got signal

    The same example but now containing all signals::

        >>> with containsignals() as C:
        ...     print("blocked {0} signals".format(len(C.oldhandlers)))
        ...     _ = signal.signal(signal.SIGBUS, signal.SIG_DFL)
        ...     # This signal is delivered when exiting the context
        ...     os.kill(os.getpid(), signal.SIGBUS)
        ...     print("no signal yet")
        blocked 29 signals
        no signal yet
        got signal

    This time, we send a signal which is not contained. We set a new
    handler, which is not blocked or changed by the context::

        >>> def fancyhandler(*args):
        ...     print("fancy!")
        >>> with containsignals([signal.SIGINT]):
        ...     _ = signal.signal(signal.SIGBUS, fancyhandler)
        ...     os.kill(os.getpid(), signal.SIGBUS)
        fancy!
        >>> os.kill(os.getpid(), signal.SIGBUS)
        fancy!

    """
    cdef public list signals
    cdef public dict oldhandlers
    cdef sigset_t unblock

    def __init__(self, signals=None):
        cdef int s
        if signals is None:
            self.signals = [s for s in range(1, 32) if s != SIGKILL and s != SIGSTOP]
        else:
            self.signals = [s for s in signals]
        self.oldhandlers = {}

    def __enter__(self):
        old = {}
        for sig in self.signals:
            try:
                h1 = signal.getsignal(sig)
                h2 = getossignal(sig)
            except (OSError, RuntimeError):
                pass
            else:
                old[sig] = (h1, h2)
        self.oldhandlers = old

        # Block all signals in self.signals during this context
        cdef sigset_t sigmask, oldmask
        sigemptyset(&sigmask)
        cdef int s
        for s in self.signals:
            sigaddset(&sigmask, s)
        if sigprocmask(SIG_BLOCK, &sigmask, &oldmask): PyErr_SetFromErrno(OSError)

        # Define self.unblock to be the sigmask corresponding to all
        # signals from self.signals which were not blocked before.
        # These signals will be unblocked again in __exit__.
        sigemptyset(&self.unblock)
        for s in self.signals:
            if not sigismember(&oldmask, s):
                sigaddset(&self.unblock, s)
        return self

    def __exit__(self, *args):
        try:
            for sig, (h1, h2) in self.oldhandlers.items():
                setsignal(sig, h1, h2)
        finally:
            if sigprocmask(SIG_UNBLOCK, &self.unblock, NULL): PyErr_SetFromErrno(OSError)


# Save Python's signal handler
with changesignal(SIGFPE, signal.default_int_handler):
    python_os_handler = getossignal(SIGFPE)
