cysignals: interrupt and signal handling for Cython
===================================================

.. image:: https://travis-ci.org/sagemath/cysignals.svg?branch=master
    :target: https://travis-ci.org/sagemath/cysignals

.. image:: https://readthedocs.org/projects/cysignals/badge/?version=latest
    :target: http://cysignals.readthedocs.org

When writing `Cython <http://cython.org/>`_ code, special care must be
taken to ensure that the code can be interrupted with ``CTRL-C``.
Since Cython optimizes for speed, Cython normally does not check for
interrupts. For example, code like the following cannot be interrupted
in Cython::

    while True:
        pass

The ``cysignals`` package provides mechanisms to handle interrupts (and other
signals and errors) in Cython code.

See http://cysignals.readthedocs.org/ for the full documentation.
