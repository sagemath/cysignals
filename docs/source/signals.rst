Handling other signals
======================

Apart from handling interrupts, :ref:`sig_on() <section_sig_on>`
provides more general signal handling.
For example, it handles :func:`alarm` time-outs by raising an
``AlarmInterrupt`` (inherited from ``KeyboardInterrupt``) exception.

If the code inside ``sig_on()`` would generate a segmentation fault or call the
C function ``abort()`` (or more generally, raise any of SIGSEGV, SIGILL,
SIGABRT, SIGFPE, SIGBUS), this is caught by the interrupt framework and an
exception is raised (``RuntimeError`` for SIGABRT, ``FloatingPointError`` for
SIGFPE and the custom exception ``SignalError``, based on ``BaseException``,
otherwise)::

    from libc.stdlib cimport abort
    from cysignals.signals cimport sig_on, sig_off

    def abort_example():
        sig_on()
        abort()
        sig_off()

.. code-block:: pycon

    >>> abort_example()
    Traceback (most recent call last):
    ...
    RuntimeError: Aborted

This exception can be handled by a ``try``/``except`` block as explained above.
A segmentation fault or ``abort()`` unguarded by ``sig_on()`` would simply
terminate the Python Interpreter. This applies only to ``sig_on()``, the
function ``sig_check()`` only deals with interrupts and alarms.

Instead of ``sig_on()``, there is also a function ``sig_str(s)``, which takes a
C string ``s`` as argument. It behaves the same as ``sig_on()``, except that the
string ``s`` will be used as a string for the exception. ``sig_str(s)`` should
still be closed by ``sig_off()``. Example Cython code::

    from libc.stdlib cimport abort
    from cysignals.signals cimport sig_str, sig_off

    def abort_example_with_sig_str():
        sig_str("custom error message")
        abort()
        sig_off()

Executing this gives:

.. code-block:: pycon

    >>> abort_example_with_sig_str()
    Traceback (most recent call last):
    ...
    RuntimeError: custom error message

With regard to ordinary interrupts (i.e. SIGINT), ``sig_str(s)`` behaves the
same as ``sig_on()``: a simple ``KeyboardInterrupt`` is raised.
