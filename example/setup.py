#!/usr/bin/env python

from setuptools import setup
from setuptools.extension import Extension
from distutils.command.build import build as _build
import sys
import os

# if on windows platform, patch distutils lib.
if sys.platform == "win32":
    utils_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), '..', 'winutil')
    sys.path.append(utils_path)
    from patchdistutils import runtime_patch
    runtime_patch()

extensions = [Extension('cysignals_example',
                        ['cysignals_example.pyx'])]


class build(_build):
    def run(self):
        dist = self.distribution
        ext_modules = dist.ext_modules
        if ext_modules:
            dist.ext_modules[:] = self.cythonize(ext_modules)
        _build.run(self)

    def cythonize(self, extensions):
        from Cython.Build.Dependencies import cythonize
        return cythonize(extensions)


setup(
    name="cysignals_example",
    version='1.0',
    license='Public Domain',
    setup_requires=["cysignals"],
    ext_modules=extensions,
    cmdclass=dict(build=build),
)
