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

cythonize_dir = "build"

kwds = dict(libraries=libraries,
            include_dirs=[os.path.join("src", "cysignals"),
                          os.path.join(cythonize_dir, "src", "cysignals")])

extensions = [
    Extension("signals", ["src/cysignals/signals.pyx"], **kwds),
    Extension("tests", ["src/cysignals/tests.pyx"], **kwds)
]

# Run Cython
extensions=cythonize(extensions, build_dir=cythonize_dir,
        include_path=["src"])

# Run Distutils
setup(
    name="cysignals",
    version='0.1dev',
    ext_package='cysignals',
    ext_modules=extensions,
    packages=["cysignals"],
    package_dir={"": "src"},
    package_data={"cysignals": ["signals.pxi"]},
    scripts=["src/scripts/signals-CSI", "src/scripts/signals-CSI-helper.py"],
    license='GNU General Public License, version 2 or later',
    long_description=open('README.rst').read(),
)
