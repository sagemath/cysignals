# -*- coding: utf-8 -*-
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

import os
import sys

have_pari = False

if have_pari:
    libraries = ["pari",  "gmp"]
    os.environ["CFLAGS"] += "-DHAVE_PARI"
else:
    libraries = []

extensions = [
    Extension("signal", ["src/signal_pyx/signal.pyx"], libraries=libraries),
    Extension("tests", ["src/signal_pyx/tests.pyx"], libraries=libraries)
]

setup(
    name="signal.pyx",
    version='0.1dev',
    ext_package='signal_pyx',
    ext_modules=cythonize(extensions, include_path=["src"]),
    packages=["signal_pyx"],
    package_dir={"signal_pyx": "src/signal_pyx"},
    package_data= {"signal_pyx": ["signal.pxi"]},
    license='GNU General Public License, version 2 or later',
    long_description=open('README.md').read(),
)
