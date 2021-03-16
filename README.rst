cysignals: interrupt and signal handling for Cython
===================================================

.. image:: https://travis-ci.org/sagemath/cysignals.svg?branch=master
    :target: https://travis-ci.org/sagemath/cysignals

.. image:: https://ci.appveyor.com/api/projects/status/vagqk56cj3ndycp4?svg=true
    :target: https://ci.appveyor.com/project/sagemath/cysignals

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

Changelog
---------

1.10.3 (2021-03-16)
^^^^^^^^^^^^^^^^^^^

* Improved installation of cysignals with ``pip install -e``. [#130]

* Fixed compilation of OpenMP modules that also use cysignals. [#128]

* Fixed segmentation fault that could occur when ``sig_occurred()`` is
  called recursively during garbage collection. [#127]

* Improved error reporting of signals that occurred inside ``sig_on()`` as
  opposed to outside them.

* Fixed bug in the ``cysignals_example`` package. [#113]

For changes in previous releases, see the best source available is to
compare git tags: https://github.com/sagemath/cysignals/tags
