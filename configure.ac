dnl Not sure which autoconf version we need, but 2.69 (from 2012)
dnl is widely available.
AC_PREREQ([2.69])

AC_DEFUN([VERSION], m4_esyscmd_s(cat VERSION))

AC_INIT([cysignals], VERSION, [https://github.com/sagemath/cysignals/issues])
AC_COPYRIGHT([GPL version 2 or later])
AC_CONFIG_SRCDIR([configure.ac])
AC_CONFIG_HEADERS([build/src/config.h:src/config.h.in])

AC_LANG(C)

AC_SEARCH_LIBS([pari_init], [pari])

AC_CHECK_HEADERS([execinfo.h sys/prctl.h])
AC_CHECK_FUNCS([backtrace])

AC_CHECK_DECL([PARI_SIGINT_block],
    [AC_DEFINE(HAVE_PARI, 1, [Define to 1 if PARI is fully supported.])],
    [], [[#include <pari/pari.h>]])

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


AC_CONFIG_COMMANDS([build/src/config.pxd],
    # Generate a file config.pxd whose contents will be copied to
    # __init__.pxd to set correct compiler options.
    # The -Ddummy works around https://github.com/cython/cython/pull/485
    [[echo "# distutils: extra_link_args = $LIBS -Ddummy" >build/src/config.pxd]],
    [LIBS=$LIBS])


AC_OUTPUT()

dnl vim:syntax=m4
