cysignals
=========

This is the documentation for **cysignals, a package to deal with
interrupts and signal handling in Cython code**.

When writing `Cython <http://cython.org/>`_ code, special care must be
taken to ensure that the code can be interrupted with ``CTRL-C``.
Since Cython optimizes for speed, Cython normally does not check for
interrupts. For example, code like the following cannot be interrupted
in Cython::

    while True:
        pass

While this is running, pressing ``CTRL-C`` has no effect. The only way
out is to kill the Python process. On certain systems, you can still
quit Python by typing ``CTRL-\`` (sending a Quit signal) instead of
``CTRL-C``.
The package cysignals provides functionality to deal with this,
see :ref:`section_interrupt`.

Besides this, cysignals also provides Python functions/classes
to deal with signals.
These are not directly related to interrupts in Cython,
but provide some supporting functionality beyond what Python provides,
see :ref:`index_python`.

Interrupt/Signal Handling
-------------------------

Dealing with interrupts and other signals using ``sig_check`` and ``sig_on``:

.. toctree::
    interrupt
    signals
    sigadvanced
    crash

Error handling
--------------

Defining error callbacks for external libraries using ``sig_error``:

.. toctree::
    sigerror

.. _index_python:

Signal-related interfaces for Python code
-----------------------------------------

cysignals provides further support for system calls related to signals:

.. toctree::
    pysignals
    pselect

Links
-----

* cysignals on the Python package index: https://pypi.org/project/cysignals/
* cysignals code repository and issue tracker on GitHub: https://github.com/sagemath/cysignals
* cysignals documentation on Read the Docs: https://cysignals.readthedocs.io
