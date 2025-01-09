# cython: preliminary_late_includes_cy28=True
r"""
Interrupt and signal handling

See ``tests.pyx`` for extensive tests.
"""

#*****************************************************************************
#       Copyright (C) 2011-2018 Jeroen Demeyer <J.Demeyer@UGent.be>
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

from libc.signal cimport *
from libc.stdio cimport freopen, stdin
from cpython.ref cimport Py_XINCREF, Py_CLEAR
from cpython.exc cimport (PyErr_Occurred, PyErr_NormalizeException,
        PyErr_Fetch, PyErr_Restore)
from cpython.version cimport PY_MAJOR_VERSION

cimport cython
import sys
from gc import collect

# On Windows, some signals are not pre-defined.
# We define them here with values that will never occur in practice
# (to avoid compilation errors and conditional compilation).
cdef extern from *:
    """
    #if defined(_WIN32) || defined(WIN32) || defined(MS_WINDOWS)
    #define NO_SUCH_SIGNAL 256
    #define SIGHUP NO_SUCH_SIGNAL
    #define SIGALRM NO_SUCH_SIGNAL
    #define SIGBUS NO_SUCH_SIGNAL
    #endif
    """
    pass

cdef extern from "implementation.c":
    cysigs_t cysigs
    int _set_debug_level(int) nogil
    void setup_alt_stack() nogil
    void setup_cysignals_handlers() nogil
    void print_backtrace() nogil
    void _sig_on_interrupt_received() nogil
    void _sig_on_recover() nogil
    void _sig_off_warning(const char*, int) nogil

    # Python library functions for raising exceptions without "except"
    # clause.
    void PyErr_SetNone(object type)
    void PyErr_SetString(object type, char *message)
    void PyErr_Format(object exception, char *format, ...)

    int (**custom_signal_is_blocked_pts)()
    void (**custom_signal_unblock_pts)()
    void (**custom_set_pending_signal_pts)(int)
    int n_custom_handlers
    int MAX_N_CUSTOM_HANDLERS


def _pari_version():
    """
    Return ``None`` to indicate that cysignals was compiled without PARI support.

    TESTS::

        sage: from cysignals.signals import _pari_version
        sage: v = _pari_version()
        sage: v is None
        True
    """
    return None


cdef int add_custom_signals(int (*custom_signal_is_blocked)() noexcept,
                            void (*custom_signal_unblock)() noexcept,
                            void (*custom_set_pending_signal)(int) noexcept) except -1:
    """
    Add an external block/unblock/pending to cysignals.

    INPUT:

    - ``custom_signal_is_blocked`` -- returns whether signals are currently blocked.

    - ``custom_signal_unblock``  -- unblocks signals

    - ``custom_set_pending_signal`` -- set a pending signal in case of blocking
    """
    global n_custom_handlers
    if n_custom_handlers == MAX_N_CUSTOM_HANDLERS:
        raise IndexError("maximal number of custom handlers exceeded")

    custom_signal_is_blocked_pts[n_custom_handlers] = custom_signal_is_blocked
    custom_signal_unblock_pts[n_custom_handlers] = custom_signal_unblock
    custom_set_pending_signal_pts[n_custom_handlers] = custom_set_pending_signal

    n_custom_handlers += 1


class AlarmInterrupt(KeyboardInterrupt):
    """
    Exception class for :func:`alarm` timeouts.

    EXAMPLES::

        >>> import platform, pytest
        >>> if platform.system() == 'Windows':
        ...     pytest.skip('this doctest does not work on Windows')
        >>> from cysignals import AlarmInterrupt
        >>> from signal import alarm
        >>> from time import sleep
        >>> try:
        ...     _ = alarm(1)
        ...     sleep(2)
        ... except AlarmInterrupt:
        ...     print("alarm!")
        alarm!
        >>> from cysignals.signals import sig_print_exception
        >>> import signal
        >>> sig_print_exception(signal.SIGALRM)
        cysignals.signals.AlarmInterrupt

    """
    pass


class SignalError(BaseException):
    """
    Exception class for critical signals such as ``SIGSEGV``. Inherits
    from ``BaseException`` because these normally should not be handled.

    EXAMPLES::

        >>> from cysignals.signals import sig_print_exception
        >>> import signal
        >>> sig_print_exception(signal.SIGSEGV)
        cysignals.signals.SignalError: Segmentation fault

    """
    pass


@cython.optimize.use_switch(False)
cdef int sig_raise_exception "sig_raise_exception"(int sig, const char* msg) except 0 with gil:
    """
    Raise an exception for signal number ``sig`` with message ``msg``
    (or a default message if ``msg`` is ``NULL``).
    """
    # Do not raise an exception if an exception is already pending
    if PyErr_Occurred():
        return 0

    # Make sure to check the standard signals from the C standard first,
    # in case systems alias some of these constants.
    if sig == SIGILL:
        if msg is NULL:
            msg = "Illegal instruction"
        PyErr_SetString(SignalError, msg)
    elif sig == SIGABRT:
        if msg is NULL:
            msg = "Aborted"
        PyErr_SetString(RuntimeError, msg)
    elif sig == SIGFPE:
        if msg is NULL:
            msg = "Floating point exception"
        PyErr_SetString(FloatingPointError, msg)
    elif sig == SIGSEGV:
        if msg is NULL:
            msg = "Segmentation fault"
        PyErr_SetString(SignalError, msg)
    elif sig == SIGINT:
        PyErr_SetNone(KeyboardInterrupt)
    elif sig == SIGTERM or sig == SIGHUP:
        # Redirect stdin from /dev/null to close interactive sessions
        _ = freopen("/dev/null", "r", stdin)
        # This causes Python to exit
        PyErr_SetNone(SystemExit)
    elif sig == SIGALRM:
        PyErr_SetNone(AlarmInterrupt)
    elif sig == SIGBUS:
        if msg is NULL:
            msg = "Bus error"
        PyErr_SetString(SignalError, msg)
    else:
        PyErr_Format(SystemError, "unknown signal number %i", sig)

    # Save exception in cysigs.exc_value
    cdef PyObject* typ = NULL
    cdef PyObject* val = NULL
    cdef PyObject* tb = NULL
    PyErr_Fetch(&typ, &val, &tb)
    PyErr_NormalizeException(&typ, &val, &tb)
    Py_XINCREF(val)
    Py_CLEAR(cysigs.exc_value)
    cysigs.exc_value = val
    PyErr_Restore(typ, val, tb)

    return 0


def sig_print_exception(sig, msg=None):
    """
    Python version of :func:`sig_raise_exception` which prints the
    exception instead of raising it. This is just for doctesting.

    EXAMPLES::

        >>> from cysignals.signals import sig_print_exception
        >>> import signal
        >>> sig_print_exception(signal.SIGFPE)
        FloatingPointError: Floating point exception
        >>> sig_print_exception(signal.SIGSEGV, "CUSTOM MESSAGE")
        cysignals.signals.SignalError: CUSTOM MESSAGE
        >>> sig_print_exception(0)
        SystemError: unknown signal number 0

    For interrupts, the message is ignored::

        >>> sig_print_exception(signal.SIGINT, "ignored")
        KeyboardInterrupt
        >>> import platform, pytest
        >>> if platform.system() == 'Windows':
        ...     pytest.skip('this doctest does not work on Windows')
        >>> sig_print_exception(signal.SIGALRM, "ignored")
        cysignals.signals.AlarmInterrupt

    """
    cdef const char* m
    if msg is None:
        m = NULL
    else:
        m = msg = msg.encode("utf-8")

    try:
        sig_raise_exception(sig, m)
    except BaseException:
        # Print exception to stdout without traceback
        import sys, traceback
        typ, val, _ = sys.exc_info()
        traceback.print_exception(typ, val, None, file=sys.stdout, chain=False)


def init_cysignals():
    """
    Initialize ``cysignals``.

    This is normally done exactly once, namely when importing
    ``cysignals``. However, it is legal to call this multiple times,
    for example when switching between the ``cysignals`` interrupt
    handler and a different interrupt handler.

    OUTPUT: the old Python-level interrupt handler

    EXAMPLES::

        >>> from cysignals.signals import init_cysignals
        >>> init_cysignals()
        <cyfunction python_check_interrupt at ...>

    """
    # Set the Python-level interrupt handler. When a SIGINT occurs,
    # this will not be called directly. Instead, a SIGINT is caught by
    # our interrupt handler, set up in implementation.c. If it happens
    # during pure Python code (not within sig_on()/sig_off()), the
    # handler will set Python's interrupt flag. Python regularly checks
    # this and will call its interrupt handler (which is the one we set
    # now). This handler issues a sig_check() which finally raises the
    # KeyboardInterrupt exception.
    import signal
    old = signal.signal(signal.SIGINT, python_check_interrupt)

    setup_alt_stack()
    setup_cysignals_handlers()

    # Set debug level to 2 by default (if debugging was enabled)
    _set_debug_level(2)

    return old


def _setup_alt_stack():
    """
    This is needed after forking on OS X because ``fork()`` disables
    the alt stack. It is not clear to me whether this is a bug or
    feature...
    """
    setup_alt_stack()


def set_debug_level(int level):
    """
    Set the cysignals debug level and return the old debug level.

    Setting this to a positive value is only allowed if cysignals was
    compiled with ``--enable-debug``.

    EXAMPLES::

        >>> from cysignals.signals import set_debug_level
        >>> old = set_debug_level(0)
        >>> set_debug_level(old)
        0

    """
    if level < 0:
        raise ValueError("cysignals debug level must be >= 0")
    cdef int r = _set_debug_level(level)
    if r == -1:
        raise RuntimeError("cysignals is compiled without debugging, recompile with --enable-debug")
    return r


def sig_on_reset():
    """
    Return the current value of ``cysigs.sig_on_count`` and set its
    value to zero. This is used by the SageMath doctesting framework.

    EXAMPLES::

        >>> import platform, pytest
        >>> if platform.system() == 'Windows':
        ...     pytest.skip('this doctest does not work on Windows')
        >>> from cysignals.signals import sig_on_reset
        >>> from cysignals.tests import _sig_on
        >>> _sig_on(); sig_on_reset()
        1
        >>> sig_on_reset()
        0

    """
    cdef int s = cysigs.sig_on_count
    cysigs.sig_on_count = 0
    return s


def python_check_interrupt(sig, frame):
    """
    Python-level interrupt handler for interrupts raised in Python
    code. This simply delegates to the interrupt handling code in
    ``implementation.c``.
    """
    sig_check()


cdef void verify_exc_value() noexcept:
    """
    Check that ``cysigs.exc_value`` is still the exception being raised.
    Clear ``cysigs.exc_value`` if not.
    """
    if cysigs.exc_value.ob_refcnt == 1:
        # No other references => exception is certainly gone
        Py_CLEAR(cysigs.exc_value)
        return

    if PyErr_Occurred() is not NULL:
        # We are being called with a live exception. Cython would never
        # call a function like that, but it could happen in
        # manually-written C code. Normally, we expect PyErr_Occurred()
        # to be the same as cysigs.exc_value. If it is a different
        # exception, it is not so clear what to do: we choose to assume
        # that the exception from cysignals has not been dealt with
        # (so there is no need to check whether the exceptions match).
        # In any case, we must avoid executing further Python code
        # (such as the collect() call below) with a live exception.
        return

    # We consider the exception in cysigs.exc_value active, even if
    # there is no actual exception (as returned by PyErr_Occurred).
    # This is to support the case where the exception is temporarily
    # disabled by a PyErr_Fetch/PyErr_Restore pair. This happens for
    # example in Cython's __dealloc__ functions.

    # There is one exception: when an exception is referenced in
    # sys.last_value, we know that it has been handled.
    # We need to check this because sys.last_value "leaks" a reference
    # to the exception.
    try:
        handled = sys.last_value
    except AttributeError:
        pass
    else:
        if <PyObject*>handled is cysigs.exc_value:
            Py_CLEAR(cysigs.exc_value)
            return

    # To be safe, we run the garbage collector because it may clear
    # references to our exception.
    try:
        collect()
    except Exception:
        # This can happen when Python is shutting down and the gc module
        # is not functional anymore.
        pass

    # Make sure we still have cysigs.exc_value at all; if this function was
    # called again during garbage collection it might have already been set
    # to NULL; see https://github.com/sagemath/cysignals/issues/126
    if cysigs.exc_value != NULL and cysigs.exc_value.ob_refcnt == 1:
        Py_CLEAR(cysigs.exc_value)
