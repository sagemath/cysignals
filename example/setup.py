#!/usr/bin/env python

from distutils.core import setup
from Cython.Build import cythonize
import sys

# Run Cython, search for .pxi files in all sys.path directories
extensions=cythonize("cysignals_example.pyx", include_path=sys.path)

# Run Distutils
setup(
    name="cysignals_example",
    version='1.0',
    ext_modules=extensions,
    license='GNU Lesser General Public License, version 3 or later',
)
