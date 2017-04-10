cysignals
=========

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

Interrupt/Signal Handling
-------------------------

Dealing with interrupts and other signals:

.. toctree::
    interrupt
    signals
    sigadvanced

Error handling
--------------

Defining error callbacks for external libraries:

.. toctree::
    sigerror
