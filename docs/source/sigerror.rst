.. _sig-error:

Error handling in C libraries
-----------------------------

Some C libraries can produce errors and use some sort of callback mechanism to
report errors: an external error handling function needs to be set up which will
be called by the C library if an error occurs.

The function ``sig_error()`` can be used to deal with these errors. This
function may only be called within a ``sig_on()`` block (otherwise the Python
interpreter will crash hard) after raising a Python exception. You need to use
the :ref:`Python/C API <python:exceptionhandling>` for this
and call ``sig_error()`` after calling some variant of :c:func:`PyErr_SetObject()`.
Even within Cython, you cannot use the ``raise`` statement, because then the
``sig_error()`` will never be executed. The call to ``sig_error()`` will use the
``sig_on()`` machinery such that the exception will be seen by ``sig_on()``.

A typical error handler implemented in Cython would look as follows::

    from cysignals.signals cimport sig_error
    from cpython.exc cimport PyErr_SetString

    cdef void error_handler(char *msg):
        PyErr_SetString(RuntimeError, msg)
        sig_error()

Exceptions which are raised this way can be handled as usual by putting
the ``sig_on()`` in a ``try``/``except`` block.
For example, the package `cypari2 <https://github.com/defeo/cypari2>`_
provides a wrapper around the number theory library PARI/GP.
The `error handler <https://github.com/defeo/cypari2/blob/master/cypari2/handle_error.pyx>`_
has a callback which turns errors from PARI/GP
into Python exceptions of type ``PariError``.
This can be handled as follows::

    from cysignals.signals cimport sig_on, sig_off
    def handle_pari_error():
        try:
            sig_on()  # This must be INSIDE the try
            # (call to PARI)
            sig_off()
        except PariError:
            # (handle error)

SageMath uses this mechanism for libGAP, GLPK, NTL and PARI.
