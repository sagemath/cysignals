cysignals: interrupt and signal handling for Cython
===================================================

.. image:: https://travis-ci.org/sagemath/cysignals.svg?branch=master
    :target: https://travis-ci.org/sagemath/cysignals

.. image:: https://readthedocs.org/projects/cysignals/badge/?version=latest
    :target: http://cysignals.readthedocs.org

Cython and interrupts
---------------------

When writing `Cython <http://cython.org/>`_ code, special care must be
taken to ensure that the code can be interrupted with ``CTRL-C``.
Since Cython optimizes for speed, Cython normally does not check for
interrupts. For example, code like the following cannot be interrupted
in Cython::

    while True:
        pass

The ``cysignals`` package provides mechanisms to handle interrupts (and other
signals and errors) in Cython code.

Requirements
------------

- Python 2.7 or Python >= 3.4
- Cython >= 0.28
- Sphinx >= 1.6 (for building the documentation)
- PARI/GP (optional; for interfacing with the PARI/GP signal handler)

Links
-----

* cysignals on the Python package index: https://pypi.org/project/cysignals/
* cysignals code repository and issue tracker on GitHub: https://github.com/sagemath/cysignals
* full cysignals documentation on Read the Docs: http://cysignals.readthedocs.io/
