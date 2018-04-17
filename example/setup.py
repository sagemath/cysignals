#!/usr/bin/env python

from setuptools import setup
from distutils.command.build import build as _build


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
    ext_modules=["cysignals_example.pyx"],
    cmdclass=dict(build=build),
)
