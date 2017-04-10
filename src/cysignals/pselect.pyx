"""
Interface to the ``pselect()`` system call
==========================================

This module defines a class :class:`PSelecter` which can be used to
call the system call ``pselect()`` and which can also be used in a
``with`` statement to block given signals until
:meth:`PSelecter.pselect` is called.

Waiting for subprocesses
------------------------

One possible use is to wait with a **timeout** until **any child process**
exits, as opposed to ``os.wait()`` which doesn't have a timeout or
``multiprocessing.Process.join()`` which waits for one specific process.

Since ``SIGCHLD`` is ignored by default, we first need to install a
signal handler for ``SIGCHLD``. It doesn't matter what it does, as long
as the signal isn't ignored::

    >>> import signal
    >>> def dummy_handler(sig, frame):
    ...     pass
    >>> _ = signal.signal(signal.SIGCHLD, dummy_handler)

We wait for a child created using the ``subprocess`` module::

    >>> from cysignals.pselect import PSelecter
    >>> from subprocess import *
    >>> with PSelecter([signal.SIGCHLD]) as sel:
    ...     p = Popen(["sleep", "1"])
    ...     _ = sel.sleep()
    >>> p.poll()  # p should be finished
    0

Now using the ``multiprocessing`` module::

    >>> from cysignals.pselect import PSelecter
    >>> from multiprocessing import *
    >>> import time
    >>> with PSelecter([signal.SIGCHLD]) as sel:
    ...     p = Process(target=time.sleep, args=(1,))
    ...     p.start()
    ...     _ = sel.sleep()
    ...     p.is_alive()  # p should be finished
    False

"""

#*****************************************************************************
#       Copyright (C) 2013 Jeroen Demeyer <jdemeyer@cage.ugent.be>
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

cimport libc.errno
from posix.signal cimport *
from posix.select cimport *
from cpython.exc cimport PyErr_SetFromErrno


def interruptible_sleep(double seconds):
    """
    Sleep for ``seconds`` seconds or until a signal arrives. This
    behaves like ``time.sleep`` from Python versions <= 3.4
    (before :pep:`475`).

    EXAMPLES::

        >>> from cysignals.pselect import interruptible_sleep
        >>> interruptible_sleep(0.5)

    We set up an alarm handler doing nothing and check that the alarm
    interrupts the sleep::

        >>> import signal, time
        >>> def alarm_handler(sig, frame):
        ...     pass
        >>> _ = signal.signal(signal.SIGALRM, alarm_handler)
        >>> t0 = time.time()
        >>> _ = signal.alarm(1)
        >>> interruptible_sleep(2)
        >>> t = time.time() - t0
        >>> (1.0 <= t <= 1.9) or t
        True

    TESTS::

        >>> interruptible_sleep(0)
        >>> interruptible_sleep(-1)
        Traceback (most recent call last):
        ...
        ValueError: sleep length must be non-negative

    Reset the signal handlers::

        >>> from cysignals import init_cysignals
        >>> _ = init_cysignals()

    """
    if seconds < 0:
        raise ValueError("sleep length must be non-negative")

    cdef fd_set rfds, wfds, xfds
    FD_ZERO(&rfds)
    FD_ZERO(&wfds)
    FD_ZERO(&xfds)

    cdef timespec tv
    tv.tv_sec = <long>seconds
    tv.tv_nsec = <long>(1e9 * (seconds - <double>tv.tv_sec))

    cdef int ret = pselect(0, &rfds, &wfds, &xfds, &tv, NULL)
    if ret < 0:
        if libc.errno.errno != libc.errno.EINTR:
            PyErr_SetFromErrno(OSError)


cpdef int get_fileno(f) except -1:
    """
    Return the file descriptor of ``f``.

    INPUT:

    - ``f`` -- an object with a ``.fileno`` method or an integer,
      which is a file descriptor.

    OUTPUT: A C ``long`` representing the file descriptor.

    EXAMPLES::

        >>> from os import devnull
        >>> from cysignals.pselect import get_fileno
        >>> get_fileno(open(devnull)) > 2
        True
        >>> get_fileno(42)
        42
        >>> get_fileno(None)
        Traceback (most recent call last):
        ...
        TypeError: an integer is required
        >>> get_fileno(-1)
        Traceback (most recent call last):
        ...
        ValueError: Invalid file descriptor
        >>> get_fileno(2**30)
        Traceback (most recent call last):
        ...
        ValueError: Invalid file descriptor

    """
    cdef int n
    try:
        n = f.fileno()
    except AttributeError:
        n = f
    if n < 0 or n >= FD_SETSIZE:
        raise ValueError("Invalid file descriptor")
    return n


cdef class PSelecter:
    """
    This class gives an interface to the ``pselect`` system call.

    It can be used in a ``with`` statement to block given signals
    such that they can only occur during the :meth:`pselect()` or
    :meth:`sleep()` calls.

    As an example, we block the ``SIGHUP`` and ``SIGALRM`` signals and
    then raise a ``SIGALRM`` signal. The interrupt will only be seen
    during the :meth:`sleep` call::

        >>> from cysignals import AlarmInterrupt
        >>> from cysignals.pselect import PSelecter
        >>> import os, signal, time
        >>> with PSelecter([signal.SIGHUP, signal.SIGALRM]) as sel:
        ...     os.kill(os.getpid(), signal.SIGALRM)
        ...     time.sleep(0.5)  # Simply sleep, no interrupt detected
        ...     try:
        ...         _ = sel.sleep(1)  # Interrupt seen here
        ...     except AlarmInterrupt:
        ...         print("Interrupt OK")
        Interrupt OK

    .. WARNING::

        If ``SIGCHLD`` is blocked inside the ``with`` block, then you
        should not use ``Popen().wait()`` or ``Process().join()``
        because those might block, even if the process has actually
        exited. Use non-blocking alternatives such as ``Popen.poll()``
        or ``multiprocessing.active_children()`` instead.
    """
    cdef sigset_t oldset
    cdef sigset_t blockset

    def __cinit__(self):
        """
        Store old signal mask, needed if this class is used *without*
        a ``with`` statement.

        EXAMPLES::

            >>> from cysignals.pselect import PSelecter
            >>> PSelecter()
            <cysignals.pselect.PSelecter ...>

        """
        cdef sigset_t emptyset
        sigemptyset(&emptyset)
        sigprocmask(SIG_BLOCK, &emptyset, &self.oldset)

    def __init__(self, block=[]):
        """
        Store list of signals to block during ``pselect()``.

        EXAMPLES::

            >>> from cysignals.pselect import PSelecter
            >>> from signal import *
            >>> PSelecter([SIGINT, SIGSEGV])
            <cysignals.pselect.PSelecter ...>

        """
        sigemptyset(&self.blockset)
        for sig in block:
            sigaddset(&self.blockset, sig)

    def __enter__(self):
        """
        Block signals chosen during :meth:`__init__` in this ``with`` block.

        OUTPUT: ``self``

        TESTS:

        Test nesting, where the inner ``with`` statements should have no
        influence, in particular they should not unblock signals which
        were already blocked upon entering::

            >>> from cysignals import AlarmInterrupt
            >>> from cysignals.pselect import PSelecter
            >>> import os, signal
            >>> with PSelecter([signal.SIGALRM]) as sel:
            ...     os.kill(os.getpid(), signal.SIGALRM)
            ...     with PSelecter([signal.SIGFPE]) as sel2:
            ...         _ = sel2.sleep(0.1)
            ...     with PSelecter([signal.SIGALRM]) as sel3:
            ...         _ = sel3.sleep(0.1)
            ...     try:
            ...         _ = sel.sleep(0.1)
            ...     except AlarmInterrupt:
            ...         print("Interrupt OK")
            Interrupt OK

        """
        sigprocmask(SIG_BLOCK, &self.blockset, &self.oldset)
        return self

    def __exit__(self, type, value, traceback):
        """
        Reset signal mask to what it was before :meth:`__enter__`.

        EXAMPLES:

        Install a ``SIGCHLD`` handler::

            >>> import signal
            >>> def child_handler(sig, frame):
            ...     global got_child
            ...     got_child = 1
            >>> _ = signal.signal(signal.SIGCHLD, child_handler)
            >>> got_child = 0

        Start a process which will cause a ``SIGCHLD`` signal::

            >>> import time
            >>> from multiprocessing import *
            >>> from cysignals.pselect import PSelecter, interruptible_sleep
            >>> w = PSelecter([signal.SIGCHLD])
            >>> with w:
            ...     p = Process(target=time.sleep, args=(0.25,))
            ...     t0 = time.time()
            ...     p.start()

        This ``sleep`` should be interruptible now::

            >>> interruptible_sleep(1)
            >>> t = time.time() - t0
            >>> (0.2 <= t <= 0.9) or t
            True
            >>> got_child
            1
            >>> p.join()

        """
        sigprocmask(SIG_SETMASK, &self.oldset, NULL)

    def pselect(self, rlist=[], wlist=[], xlist=[], timeout=None):
        """
        Wait until one of the given files is ready, or a signal has
        been received, or until ``timeout`` seconds have past.

        INPUT:

        - ``rlist`` -- (default: ``[]``) a list of files to wait for
          reading.

        - ``wlist`` -- (default: ``[]``) a list of files to wait for
          writing.

        - ``xlist`` -- (default: ``[]``) a list of files to wait for
          exceptions.

        - ``timeout`` -- (default: ``None``) a timeout in seconds,
          where ``None`` stands for no timeout.

        OUTPUT: A 4-tuple ``(rready, wready, xready, tmout)`` where the
        first three are lists of file descriptors which are ready,
        that is a subset of ``(rlist, wlist, xlist)``. The fourth is a
        boolean which is ``True`` if and only if the command timed out.
        If ``pselect`` was interrupted by a signal, the output is
        ``([], [], [], False)``.

        .. SEEALSO::

            Use the :meth:`sleep` method instead if you don't care about
            file descriptors.

        EXAMPLES:

        The file ``/dev/null`` should always be available for reading
        and writing::

            >>> from cysignals.pselect import PSelecter
            >>> f = open(os.devnull, "r+")
            >>> sel = PSelecter()
            >>> sel.pselect(rlist=[f])
            ([<...'/dev/null'...>], [], [], False)
            >>> sel.pselect(wlist=[f])
            ([], [<...'/dev/null'...>], [], False)

        A list of various files, all of them should be ready for
        reading. Also create a pipe, which should be ready for
        writing, but not reading (since nothing has been written)::

            >>> import os, sys
            >>> f = open(os.devnull, "r")
            >>> g = open(sys.executable, "r")
            >>> (pr, pw) = os.pipe()
            >>> r, w, x, t = PSelecter().pselect([f,g,pr,pw], [pw], [pr,pw])
            >>> len(r), len(w), len(x), t
            (2, 1, 0, False)

        Checking for exceptions on the pipe should simply time out::

            >>> sel.pselect(xlist=[pr,pw], timeout=0.2)
            ([], [], [], True)

        TESTS:

        It is legal (but silly) to list the same file multiple times::

            >>> r, w, x, t = PSelecter().pselect([f,g,f,f,g])
            >>> len(r)
            5

        Invalid input::

            >>> PSelecter().pselect([None])
            Traceback (most recent call last):
            ...
            TypeError: an integer is required

        Open a file and close it, but save the (invalid) file
        descriptor::

            >>> f = open(os.devnull, "r")
            >>> n = f.fileno()
            >>> f.close()
            >>> PSelecter().pselect([n])
            Traceback (most recent call last):
            ...
            OSError: ...

        """
        # Convert given lists to fd_set
        cdef fd_set rfds, wfds, xfds
        FD_ZERO(&rfds)
        FD_ZERO(&wfds)
        FD_ZERO(&xfds)

        cdef int nfds = 0
        cdef int n
        for f in rlist:
            n = get_fileno(f)
            if (n >= nfds): nfds = n + 1
            FD_SET(n, &rfds)
        for f in wlist:
            n = get_fileno(f)
            if (n >= nfds): nfds = n + 1
            FD_SET(n, &wfds)
        for f in xlist:
            n = get_fileno(f)
            if (n >= nfds): nfds = n + 1
            FD_SET(n, &xfds)

        cdef double tm
        cdef timespec tv
        cdef timespec *ptv = NULL
        cdef int ret
        if timeout is not None:
            tm = timeout
            if tm < 0:
                tm = 0
            tv.tv_sec = <long>tm
            tv.tv_nsec = <long>(1e9 * (tm - <double>tv.tv_sec))
            ptv = &tv

        ret = pselect(nfds, &rfds, &wfds, &xfds, ptv, &self.oldset)
        # No file descriptors ready => timeout
        if ret == 0:
            return ([], [], [], True)

        # Error?
        if ret < 0:
            if libc.errno.errno == libc.errno.EINTR:
                return ([], [], [], False)
            PyErr_SetFromErrno(OSError)

        # Figure out which file descriptors to return
        rready = []
        wready = []
        xready = []
        for f in rlist:
            n = get_fileno(f)
            if FD_ISSET(n, &rfds):
                rready.append(f)
        for f in wlist:
            n = get_fileno(f)
            if FD_ISSET(n, &wfds):
                wready.append(f)
        for f in xlist:
            n = get_fileno(f)
            if FD_ISSET(n, &xfds):
                xready.append(f)

        return (rready, wready, xready, False)

    def sleep(self, timeout=None):
        """
        Wait until a signal has been received, or until ``timeout``
        seconds have past.

        This is implemented as a special case of :meth:`pselect` with
        empty lists of file descriptors.

        INPUT:

        - ``timeout`` -- (default: ``None``) a timeout in seconds,
          where ``None`` stands for no timeout.

        OUTPUT: A boolean which is ``True`` if the call timed out,
        False if it was interrupted.

        EXAMPLES:

        A simple wait with timeout::

            >>> from cysignals.pselect import PSelecter
            >>> sel = PSelecter()
            >>> sel.sleep(timeout=0.1)
            True

        0 or negative time-outs are allowed, ``sleep`` should then
        return immediately::

            >>> sel.sleep(timeout=0)
            True
            >>> sel.sleep(timeout=-123.45)
            True

        """
        return self.pselect(timeout=timeout)[3]
