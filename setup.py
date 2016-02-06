# -*- coding: utf-8 -*-
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

import os


have_pari = False

if have_pari:
    libraries = ["pari",  "gmp"]
    os.environ["CFLAGS"] += "-DHAVE_PARI"
else:
    libraries = []

extensions = [
    Extension("interrupt", ["src/interrupt.pyx"], libraries=libraries),
]

setup(
    name="signal.pyx",
    version='0.1dev',
    ext_package='signal',
    ext_modules=cythonize(extensions, include_path=["src"]),
    package_dir={"": "src"},
    packages=["."],
    license='GNU General Public License, version 2 or later',
    long_description=open('README.md').read(),
)
