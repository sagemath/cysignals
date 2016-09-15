dnl Not sure which autoconf version we need, but 2.69 (from 2012)
dnl is widely available.
AC_PREREQ([2.69])
AC_COPYRIGHT([GNU Lesser General Public License version 3 or later])

AC_DEFUN([VERSION], m4_esyscmd_s(cat VERSION))

AC_INIT([cysignals], VERSION, [https://github.com/sagemath/cysignals/issues])
AC_CONFIG_MACRO_DIR([m4])
AC_CONFIG_SRCDIR([src/cysignals/pxi.h])
AC_CONFIG_HEADERS([src/config.h])

AC_LANG(C)

AC_CHECK_HEADERS([execinfo.h sys/prctl.h])
AC_CHECK_FUNCS([backtrace])

AM_PATH_PARI([2.8],
	[AC_DEFINE(HAVE_PARI, 1, [Define to 1 if PARI is fully supported.])],
	[AC_MSG_WARN([no suitable PARI library found])])

AC_MSG_CHECKING([for emms instruction])
# We add the "leal" instruction to reduce false positives in case some
# non-x86 architecture also has an "emms" instruction.
AC_RUN_IFELSE([AC_LANG_PROGRAM([], [asm("leal (%eax), %eax; emms");])],
    dnl YES
    [AC_MSG_RESULT([yes])]
    AC_DEFINE(HAVE_EMMS, 1, [Define to 1 if your processor understands the "emms" instruction.])
    ,
    dnl NO
    [AC_MSG_RESULT([no])]
)


AC_CONFIG_COMMANDS([src/config.pxd],
    # Generate a file config.pxd whose contents will be copied to
    # __init__.pxd to set correct compiler options.
    # The -DCYSIGNALS_DUMMY works around https://github.com/cython/cython/pull/485
    [[
			echo "# distutils: extra_compile_args = $EXTRACOMPILEARGS" > src/config.pxd
			echo "# distutils: extra_link_args = -DCYSIGNALS_DUMMY $EXTRALINKARGS" >> src/config.pxd
		]],
    [
			EXTRACOMPILEARGS="$PARI_CPPFLAGS $PARI_CFLAGS"
			EXTRALINKARGS="$PARI_LDFLAGS $PARI_LIBS"
		])


AC_OUTPUT()

dnl vim:syntax=m4
