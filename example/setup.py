#!/usr/bin/env python

from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize


# Run Cython
extensions=cythonize("cysignals_example.pyx")

# Run Distutils
setup(
    name="cysignals_example",
    version='1.0',
    ext_modules=extensions,
    license='GNU General Public License, version 2 or later',
)
