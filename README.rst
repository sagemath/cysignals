cysignals: interrupt and signal handling for Cython
===================================================

.. image:: https://readthedocs.org/projects/cysignals/badge/?version=latest
    :target: https://cysignals.readthedocs.org

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

- Python >= 3.9
- Cython >= 0.28
- Sphinx >= 1.6 (for building the documentation)

Links
-----

* cysignals on the Python package index: https://pypi.org/project/cysignals/
* cysignals code repository and issue tracker on GitHub: https://github.com/sagemath/cysignals
* full cysignals documentation on Read the Docs: http://cysignals.readthedocs.io/

Changelog
---------

1.12.0 (release candidate)
^^^^^^^^^^^^^^^^^^^^^^^^^^

* Remove optional compile-time dependency on PARI/GP. [#166]


1.11.4 (2023-10-07)
^^^^^^^^^^^^^^^^^^^

* Include generated `configure` script in the sdist again.


1.11.3 (2023-10-04)
^^^^^^^^^^^^^^^^^^^

* Add support for Cython 3. [#174, #176, #182, #187]
* Add support for Python 3.12.
* Replace `fprintf` by calls to `write`, which is async-signal-safe according to POSIX. [#162]
* Introduce a general hook to interface with custom signal handling. [#181]


1.11.2 (2021-12-15)
^^^^^^^^^^^^^^^^^^^

* Drop assembly code added after 1.10.3 that is not portable.


1.11.0 (2021-11-26)
^^^^^^^^^^^^^^^^^^^

* Drop Python 2 support; bump minimum Python version to 3.6. [#142]
* Fixed compilation with glib 3.34. [#151]
* Improved testing. [#139, #152, #154]


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
