#!/usr/bin/env python

from distutils.core import setup
from Cython.Build import cythonize
import sys

extensions=cythonize("cysignals_example.pyx")

# Run Distutils
setup(
    name="cysignals_example",
    version='1.0',
    ext_modules=extensions,
    license='GNU Lesser General Public License, version 3 or later',
)
