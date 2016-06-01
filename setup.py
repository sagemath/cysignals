#!/usr/bin/env python
# -*- coding: utf-8 -*-
from distutils.core import setup, Distribution
from distutils.command.build_py import build_py
from distutils.extension import Extension
from Cython.Build import cythonize

import warnings
warnings.simplefilter("always")

import os
from glob import glob

opj = os.path.join


cythonize_dir = "build"

kwds = dict(include_dirs=[opj("src", "cysignals"),
                          opj(cythonize_dir, "src"),
                          opj(cythonize_dir, "src", "cysignals")],
            depends=glob(opj("src", "cysignals", "*.h")))

extensions = [
    Extension("cysignals.signals", ["src/cysignals/signals.pyx"], **kwds),
    Extension("cysignals.alarm", ["src/cysignals/alarm.pyx"], **kwds),
    Extension("cysignals.tests", ["src/cysignals/tests.pyx"], **kwds)
]


# Run configure if it wasn't run before. We check this by the presence
# of config.pxd
config_pxd_file = opj(cythonize_dir, "src", "config.pxd")
if not os.path.isfile(config_pxd_file):
    import subprocess
    subprocess.check_call(["make", "configure"])
    subprocess.check_call(["sh", "configure"])


# Determine installation directory from distutils
inst = Distribution().get_command_obj("install")
inst.finalize_options()
install_dir = opj(inst.install_platlib, "cysignals")


# Add an __init__.pxd file setting the correct compiler options.
# The variable "init_pxd" is the string which should be written to
# __init__.pxd
init_pxd = "# distutils: include_dirs = {0}\n".format(install_dir)
# Append config.pxd
with open(config_pxd_file) as c:
    init_pxd += c.read()

# First, try to read the existing __init__.pxd file and write it only
# if it changed.
init_pxd_file = opj(cythonize_dir, "src", "cysignals", "__init__.pxd")
try:
    f = open(init_pxd_file, "r+")
except IOError:
    try:
        os.makedirs(os.path.dirname(init_pxd_file))
    except OSError:
        pass
    f = open(init_pxd_file, "w+")

if f.read() != init_pxd:
    print("generating {0}".format(init_pxd_file))
    f.seek(0)
    f.truncate()
    f.write(init_pxd)
f.close()


# Run Cython
extensions=cythonize(extensions, build_dir=cythonize_dir,
                     include_path=["src", opj(cythonize_dir, "src")])

# Deprecate Cython without https://github.com/cython/cython/pull/486
if os.path.isdir(opj(cythonize_dir, "cysignals")):
    warnings.warn(
        "building cysignals with Cython versions older than 0.24 is deprecated, "
        "you should upgrade Cython and remove the %r directory" % cythonize_dir,
        DeprecationWarning)

# Fix include_dirs (i.e. ignore the __init__.pxd for this compilation)
for ext in extensions:
    ext.include_dirs = kwds['include_dirs']


# Run Distutils
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
    author=u"Martin R. Albrecht, François Bissey, Volker Braun, Jeroen Demeyer",
    author_email="sage-devel@googlegroups.com",
    version=open("VERSION").read().strip(),
    url="https://github.com/sagemath/cysignals",
    license="GNU Lesser General Public License, version 3 or later",
    description="Interrupt and signal handling for Cython",
    long_description=open('README.rst').read(),
    platforms=["POSIX"],

    ext_modules=extensions,
    packages=["cysignals"],
    package_dir={"cysignals": opj("src", "cysignals"),
                 "cysignals-cython": opj(cythonize_dir, "src", "cysignals")},
    package_data={"cysignals": ["*.pxi", "*.pxd", "*.h"],
                  "cysignals-cython": ["__init__.pxd", "*.h"]},
    scripts=glob(opj("src", "scripts", "*")),
    cmdclass=dict(build_py=build_py_cython),
)
