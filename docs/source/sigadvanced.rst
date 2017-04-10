Further topics in interrupt/signal handling
===========================================

Testing interrupts
------------------

When writing documentation, one sometimes wants to check that certain
code can be interrupted in a clean way. The best way to do this is to
use :func:`cysignals.alarm`.

The following is an example of a doctest demonstrating that the
SageMath function :func:`factor()` can be interrupted:

.. code-block:: pycon

    >>> from cysignals.alarm import alarm, AlarmInterrupt
    >>> try:
    ...     alarm(0.5)
    ...     factor(10**1000 + 3)
    ... except AlarmInterrupt:
    ...     print("alarm!")
    alarm!

If you use the SageMath doctesting framework, you can instead doctest
the exception in the usual way. To avoid race conditions, make sure
that the calls to ``alarm()`` and the function you want to test are in
the same doctest:

.. code-block:: pycon

    >>> alarm(0.5); factor(10**1000 + 3)
    Traceback (most recent call last):
    ...
    AlarmInterrupt

.. _advanced-sig:

Signal handling without exceptions
----------------------------------

There are several more specialized functions for dealing with interrupts. As
mentioned above, ``sig_on()`` makes no attempt to clean anything up (restore
state or freeing memory) when an interrupt occurs. In fact, it would be
impossible for ``sig_on()`` to do that. If you want to add some cleanup code,
use ``sig_on_no_except()`` for this. This function behaves *exactly* like
``sig_on()``, except that any exception raised (like ``KeyboardInterrupt`` or
``RuntimeError``) is not yet passed to Python. Essentially, the exception is
there, but we prevent Cython from looking for the exception. Then
``cython_check_exception()`` can be used to make Cython look for the exception.

Normally, ``sig_on_no_except()`` returns 1. If a signal was caught and an
exception raised, ``sig_on_no_except()`` instead returns 0. The following
example shows how to use ``sig_on_no_except()``::

    def no_except_example():
        if not sig_on_no_except():
            # (clean up messed up internal state)

            # Make Cython realize that there is an exception.
            # It will look like the exception was actually raised
            # by cython_check_exception().
            cython_check_exception()
        # (some long computation, messing up internal state of objects)
        sig_off()

There is also a function ``sig_str_no_except(s)`` which is analogous to
``sig_str(s)``.

.. NOTE::

    See the file `src/cysignals/tests.pyx <https://github.com/sagemath/cysignals/blob/master/src/cysignals/tests.pyx>`_
    for more examples of how to use the various ``sig_*()`` functions.

Releasing the Global Interpreter Lock (GIL)
-------------------------------------------

All the functions related to interrupt and signal handling do not require the
`Python GIL
<http://docs.cython.org/src/userguide/external_C_code.html#acquiring-and-releasing-the-gil>`_
(if you don't know what this means, you can safely ignore this section), they
are declared ``nogil``. This means that they can be used in Cython code inside
``with nogil`` blocks. If ``sig_on()`` needs to raise an exception, the GIL is
temporarily acquired internally.

If you use C libraries without the GIL and you want to raise an exception before
calling :ref:`sig_error() <sig-error>`, remember to acquire the GIL while
raising the exception. Within Cython, you can use a `with gil context
<http://docs.cython.org/src/userguide/external_C_code.html#acquiring-the-gil>`_.

.. WARNING::

    The GIL should never be released or acquired inside a ``sig_on()`` block. If
    you want to use a ``with nogil`` block, put both ``sig_on()`` and
    ``sig_off()`` inside that block. When in doubt, choose to use
    ``sig_check()`` instead, which is always safe to use.

