.. _section_interrupt:

Interrupt handling
==================

cysignals provides two related mechanisms to deal with interrupts:

* Use :ref:`sig_check() <section_sig_check>` if you are writing mixed
  Cython/Python code. Typically this is code with (nested) loops where every
  individual statement takes little time.

* Use :ref:`sig_on() and sig_off() <section_sig_on>` if you are calling external
  C libraries or inside pure Cython code (without any Python functions) where
  even an individual statement, like a library call, can take a long time.

The functions ``sig_check()``, ``sig_on()`` and ``sig_off()`` can be put in all
kinds of Cython functions: ``def``, ``cdef`` or ``cpdef``. You cannot put them
in pure Python code (files with extension ``.py``).

Basic example
-------------

The ``sig_check()`` in the loop below ensures that the loop can be
interrupted by ``CTRL-C``::

    from cysignals.signals cimport sig_check
    from libc.math cimport sin

    def sine_sum(double x, long count):
        cdef double s = 0
        for i in range(count):
            sig_check()
            s += sin(i*x)
        return s

See the `example <https://github.com/sagemath/cysignals/tree/master/example>`_
directory for this complete working example.

.. NOTE::

    Cython ``cdef`` or ``cpdef`` functions with a return type (like ``cdef int
    myfunc():``) need to have an `except value
    <http://docs.cython.org/src/userguide/language_basics.html#error-return-values>`_
    to propagate exceptions. Remember this whenever you write ``sig_check()`` or
    ``sig_on()`` inside such a function, otherwise you will see a message like
    ``Exception KeyboardInterrupt: KeyboardInterrupt() in <function name>
    ignored``.

.. _section_sig_check:

Using ``sig_check()``
---------------------

``sig_check()`` can be used to check for pending interrupts. If an interrupt
happens during the execution of C or Cython code, it will be caught by the next
``sig_check()``, the next ``sig_on()`` or possibly the next Python statement.
With the latter we mean that certain Python statements also check for
interrupts, an example of this is the ``print`` statement. The following loop
*can* be interrupted:

.. code-block:: pycon

    >>> while True:
    ...     print("Hello")

The typical use case for ``sig_check()`` is within tight loops doing complicated
stuff (mixed Python and Cython code, potentially raising exceptions). It is
reasonably safe to use and gives a lot of control, because in your Cython code,
a ``KeyboardInterrupt`` can *only* be raised during ``sig_check()``::

    from cysignals.signals cimport sig_check
    def sig_check_example():
        for x in foo:
            # (one loop iteration which does not take a long time)
            sig_check()

This ``KeyboardInterrupt`` is treated like any other Python exception and can be
handled as usual::

    from cysignals.signals cimport sig_check
    def catch_interrupts():
        try:
            while some_condition():
                sig_check()
                do_something()
        except KeyboardInterrupt:
            # (handle interrupt)

Of course, you can also put the ``try``/``except`` inside the loop in the
example above.

The function ``sig_check()`` is an extremely fast inline function which should
have no measurable effect on performance.

.. _section_sig_on:

Using ``sig_on()`` and ``sig_off()``
------------------------------------

Another mechanism for interrupt handling is the pair of functions ``sig_on()``
and ``sig_off()``. It is more powerful than ``sig_check()`` but also a lot more
dangerous. You should put ``sig_on()`` *before* and ``sig_off()`` *after* any
Cython code which could potentially take a long time. These two *must always* be
called in **pairs**, i.e. every ``sig_on()`` must be matched by a closing
``sig_off()``.

In practice your function will probably look like::

    from cysignals.signals cimport sig_on, sig_off
    def sig_example():
        # (some harmless initialization)
        sig_on()
        # (a long computation here, potentially calling a C library)
        sig_off()
        # (some harmless post-processing)
        return something

It is possible to put ``sig_on()`` and ``sig_off()`` in different functions,
provided that ``sig_off()`` is called before the function which calls
``sig_on()`` returns. The following code is *invalid*::

    # INVALID code because we return from function foo()
    # without calling sig_off() first.
    cdef foo():
        sig_on()

    def f1():
        foo()
        sig_off()

But the following is valid since you cannot call ``foo`` interactively::

    from cysignals.signals cimport sig_on, sig_off

    cdef int foo():
        sig_off()
        return 2+2

    def f1():
        sig_on()
        return foo()

For clarity however, it is best to avoid this.

A common mistake is to put ``sig_off()`` towards the end of a function (before
the ``return``) when the function has multiple ``return`` statements. So make
sure there is a ``sig_off()`` before *every* ``return`` (and also before every
``raise``).

.. WARNING::

    The code inside ``sig_on()`` should be pure C or Cython code. If you call
    any Python code or manipulate any Python object (even something trivial like
    ``x = []``), an interrupt can mess up Python's internal state. When in
    doubt, try to use :ref:`sig_check() <section_sig_check>` instead.

    Also, when an interrupt occurs inside ``sig_on()``, code execution
    immediately stops without cleaning up. For example, any memory allocated
    inside ``sig_on()`` is lost. See :ref:`advanced-sig` for ways to deal with
    this.

When the user presses ``CTRL-C`` inside ``sig_on()``, execution will jump back
to ``sig_on()`` (the first one if there is a stack) and ``sig_on()`` will raise
``KeyboardInterrupt``. As with ``sig_check()``, this exception can be handled in
the usual way::

    from cysignals.signals cimport sig_on, sig_off
    def catch_interrupts():
        try:
            sig_on()  # This must be INSIDE the try
            # (some long computation)
            sig_off()
        except KeyboardInterrupt:
            # (handle interrupt)

It is possible to stack ``sig_on()`` and ``sig_off()``. If you do this, the
effect is exactly the same as if only the outer ``sig_on()``/``sig_off()`` was
there. The inner ones will just change a reference counter and otherwise do
nothing. Make sure that the number of ``sig_on()`` calls equal the number of
``sig_off()`` calls::

    from cysignals.signals cimport sig_on, sig_off

    def f1():
        sig_on()
        x = f2()
        sig_off()

    cdef f2():
        sig_on()
        # ...
        sig_off()
        return ans

Extra care must be taken with exceptions raised inside ``sig_on()``. The problem
is that, if you do not do anything special, the ``sig_off()`` will never be
called if there is an exception. If you need to *raise* an exception yourself,
call a ``sig_off()`` before it::

    from cysignals.signals cimport sig_on, sig_off
    def raising_an_exception():
        sig_on()
        # (some long computation)
        if (something_failed):
            sig_off()
            raise RuntimeError("something failed")
        # (some more computation)
        sig_off()
        return something

Alternatively, you can use ``try``/``finally`` which will also catch exceptions
raised by subroutines inside the ``try``::

    from cysignals.signals cimport sig_on, sig_off
    def try_finally_example():
        sig_on()  # This must be OUTSIDE the try
        try:
            # (some long computation, potentially raising exceptions)
            return something
        finally:
            sig_off()

If you want to also catch this exception, you need a nested ``try``::

    from cysignals.signals cimport sig_on, sig_off
    def try_finally_and_catch_example():
        try:
            sig_on()
            try:
                # (some long computation, potentially raising exceptions)
            finally:
                sig_off()
        except Exception:
            print("Trouble! Trouble!")

``sig_on()`` is implemented using the C library call ``setjmp()`` which takes a
very small but still measurable amount of time. In very time-critical code, one
can conditionally call ``sig_on()`` and ``sig_off()``::

    from cysignals.signals cimport sig_on, sig_off
    def conditional_sig_on_example(long n):
        if n > 100:
            sig_on()
        # (do something depending on n)
        if n > 100:
            sig_off()

This should only be needed if both the check (``n > 100`` in the example) and
the code inside the ``sig_on()`` block take very little time.
