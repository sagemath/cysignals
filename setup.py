#!/usr/bin/env python
# -*- coding: utf-8 -*-
from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

import os
import sys
import sysconfig
from glob import glob

opj = os.path.join


have_pari = False

libraries = []
extra_compile_args = []

if have_pari:
    libraries += ["pari",  "gmp"]
    extra_compile_args += ["-DHAVE_PARI"]

cythonize_dir = "build"

kwds = dict(libraries=libraries,
            include_dirs=[opj("src", "cysignals"),
                          opj(cythonize_dir, "src", "cysignals")],
            depends=glob(opj("src", "cysignals", "*.h")),
            extra_compile_args=extra_compile_args)

extensions = [
    Extension("signals", ["src/cysignals/signals.pyx"], **kwds),
    Extension("tests", ["src/cysignals/tests.pyx"], **kwds)
]


# Add an __init__.pxd file setting the correct include path
try:
    os.makedirs(opj(cythonize_dir, "src", "cysignals"))
except OSError:
    pass
install_dir = opj(sysconfig.get_path("platlib"), "cysignals")
with open(opj(cythonize_dir, "src", "cysignals", "__init__.pxd"), "wt") as f:
    f.write("# distutils: include_dirs = {0}\n".format(install_dir))


# Run Cython
extensions=cythonize(extensions, build_dir=cythonize_dir,
                     include_path=["src", opj(cythonize_dir, "src")])


# Run Distutils
from distutils.command.build_py import build_py
class build_py_cython(build_py):
    """
    Custom distutils build_py class. For every package FOO, we also
    check package data for a "fake" FOO-cython package.
    """
    def get_data_files(self):
        """Generate list of '(package,src_dir,build_dir,filenames)' tuples"""
        data = []
        if not self.packages:
            return data
        for package in self.packages:
            for src_package in [package, package + "-cython"]:
                # Locate package source directory
                src_dir = self.get_package_dir(src_package)

                # Compute package build directory
                build_dir = os.path.join(*([self.build_lib] + package.split('.')))

                # Length of path to strip from found files
                plen = 0
                if src_dir:
                    plen = len(src_dir)+1

                # Strip directory from globbed filenames
                filenames = [
                    file[plen:] for file in self.find_data_files(src_package, src_dir)
                    ]
                data.append((package, src_dir, build_dir, filenames))
        return data

setup(
    name="cysignals",
    version='0.1dev',
    ext_package='cysignals',
    ext_modules=extensions,
    packages=["cysignals"],
    package_dir={"cysignals": opj("src", "cysignals"),
                 "cysignals-cython": opj(cythonize_dir, "src", "cysignals")},
    package_data={"cysignals": ["*.pxi", "*.pxd", "*.h"],
                  "cysignals-cython": ["__init__.pxd", "*.h"]},
    scripts=glob(opj("src", "scripts", "*")),
    cmdclass=dict(build_py=build_py_cython),
    license='GNU General Public License, version 2 or later',
    long_description=open('README.rst').read(),
)
