#!/usr/bin/env python
# -*- coding: utf-8 -*-
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

import os
import sys
from glob import glob

have_pari = False

libraries = []
extra_compile_args = []

if have_pari:
    libraries += ["pari",  "gmp"]
    extra_compile_args += ["-DHAVE_PARI"]

cythonize_dir = "build"

kwds = dict(libraries=libraries,
            include_dirs=[os.path.join("src", "cysignals"),
                          os.path.join(cythonize_dir, "src", "cysignals")],
            depends=glob(os.path.join("src", "cysignals", "*.h")),
            extra_compile_args=extra_compile_args)

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
    package_data={"cysignals": ["signals.pxi", "signals.pxd"]},
    data_files=[(os.path.join(sys.prefix, "include"), ["src/cysignals/struct_signals.h",
                                                       "src/cysignals/debug.h",
                                                       "src/cysignals/macros.h",
                                                       "src/cysignals/pxi.h",
                                                       "build/src/cysignals/signals_api.h",
                                                       "build/src/cysignals/signals.h"])],
    scripts=glob("src/scripts/*"),
    license='GNU General Public License, version 2 or later',
    long_description=open('README.rst').read(),
)
