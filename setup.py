#!/usr/bin/env python
# -*- coding: utf-8 -*-
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

import os

have_pari = False

if have_pari:
    libraries = ["pari",  "gmp"]
    os.environ["CFLAGS"] += " -DHAVE_PARI "
else:
    libraries = []

extensions = [
    Extension("signals", ["src/cysignals/signals.pyx"], libraries=libraries),
    Extension("tests", ["src/cysignals/tests.pyx"], libraries=libraries)
]

setup(
    name="cysignals",
    version='0.1dev',
    ext_package='cysignals',
    ext_modules=cythonize(extensions, include_path=["src"]),
    packages=["cysignals"],
    package_dir={"": "src"},
    package_data={"cysignals": ["signals.pxi"]},
    scripts=["src/scripts/signals-CSI", "src/scripts/signals-CSI-helper.py"],
    license='GNU General Public License, version 2 or later',
    long_description=open('README.rst').read(),
)
