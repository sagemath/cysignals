#!/usr/bin/env python
"""
This script 'monkey patch' distutils on windows platform.
With python 32 bits distutils is patched to use mingw32 compiler
With python 64 bits distutils is patched to use mingw64 compiler

This script has been tested with the following version :
python2.7.14, python2.7.14-64bits, python3.4.4, python3.4.4-64bits
"""
__author__ = "Vincent Klein"

import sys
from distutils.cygwinccompiler import CygwinCCompiler, is_cygwingcc


# the same as cygwin plus some additional parameters
class Mingw64CCompiler(CygwinCCompiler):

    compiler_type = 'mingw64'

    def __init__(self,
                  verbose=0,
                  dry_run=0,
                  force=0):

        CygwinCCompiler.__init__(self, verbose, dry_run, force)

        # ld_version >= "2.13" support -shared so use it instead of
        # -mdll -static
        if self.ld_version >= "2.13":
            shared_option = "-shared"
        else:
            shared_option = "-mdll -static"

        # A real mingw32 doesn't need to specify a different entry point,
        # but cygwin 2.91.57 in no-cygwin-mode needs it.
        if self.gcc_version <= "2.91.57":
            entry_point = '--entry _DllMain@12'
        else:
            entry_point = ''

        if self.gcc_version < '4' or is_cygwingcc():
            no_cygwin = ' -mno-cygwin'
        else:
            no_cygwin = ''

        self.linker_dll = 'x86_64-w64-mingw32-gcc'

        self.set_executables(compiler='x86_64-w64-mingw32-gcc%s -O -Wall' % no_cygwin,
                             compiler_so='x86_64-w64-mingw32-gcc%s -mdll -O -Wall -D MS_WIN64' % no_cygwin,
                             compiler_cxx='x86_64-w64-mingw32-g++%s -O -Wall' % no_cygwin,
                             linker_exe='x86_64-w64-mingw32-gcc%s' % no_cygwin,
                             linker_so='%s%s %s %s'
                                    % (self.linker_dll, no_cygwin,
                                       shared_option, entry_point))
        # Maybe we should also append -mthreads, but then the finished
        # dlls need another dll (mingwm10.dll see Mingw32 docs)
        # (-mthreads: Support thread-safe exception handling on `Mingw32')

        # no additional libraries needed
        self.dll_libraries=[]

        # Include the appropriate MSVC runtime library if Python was built
        # with MSVC 7.0 or later.
        #self.dll_libraries = get_msvcr()

    # __init__ ()


def get_msvcr():
    """Include the appropriate MSVC runtime library if Python was built
    with MSVC 7.0 or later.
    """
    msc_pos = sys.version.find('MSC v.')
    if msc_pos != -1:
        msc_ver = sys.version[msc_pos+6:msc_pos+10]
        if msc_ver == '1300':
            # MSVC 7.0
            return ['msvcr70']
        elif msc_ver == '1310':
            # MSVC 7.1
            return ['msvcr71']
        elif msc_ver == '1400':
            # VS2005 / MSVC 8.0
            return ['msvcr80']
        elif msc_ver == '1500':
            # VS2008 / MSVC 9.0
            return ['msvcr90']
        elif msc_ver == '1600':
            # VS2010 / MSVC 10.0
            return ['msvcr100']
        elif msc_ver == '1700':
            # Visual Studio 2012 / Visual C++ 11.0
            return ['msvcr110']
        elif msc_ver == '1800':
            # Visual Studio 2013 / Visual C++ 12.0
            return ['msvcr120']
        elif msc_ver == '1900':
            # Visual Studio 2015 / Visual C++ 14.0
            # "msvcr140.dll no longer exists" http://blogs.msdn.com/b/vcblog/archive/2014/06/03/visual-studio-14-ctp.aspx
            return []
        else:
            raise ValueError("Unknown MS Compiler version %s " % msc_ver)


def runtime_patch():
    """
    Apply the monkey patch
    """
    import struct
    import distutils.cygwinccompiler as cygwinccompiler
    import distutils.ccompiler as ccompiler

    # compiler type for python 32bits
    compiler = 'mingw32'
    bit_version = struct.calcsize("P") * 8

    if bit_version == 64:  # Python 64 bits
        from distutils.ccompiler import compiler_class

        cygwinccompiler.Mingw64CCompiler = Mingw64CCompiler
        compiler_class['mingw64'] = ('cygwinccompiler', 'Mingw64CCompiler', "Mingw64 port of GNU C Compiler for Win64")

        compiler = 'mingw64'

    # get_msvcr() function should be patched for python version >= 3.5
    if sys.version_info[0] == 3 and sys.version_info[1] >= 5:
        cygwinccompiler.get_msvcr = get_msvcr

    # change default compiler for nt
    ccompiler._default_compilers = (('nt', compiler),)
