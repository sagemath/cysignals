dnl Not sure which autoconf version we need, but 2.68 (from 2010)
dnl is widely available.
AC_PREREQ([2.68])

AC_DEFUN([VERSION], m4_esyscmd_s(cat VERSION))

AC_INIT([cysignals], VERSION, [https://github.com/sagemath/cysignals/issues])
AC_COPYRIGHT([GNU Lesser General Public License version 3 or later])
AC_CONFIG_SRCDIR([configure.ac])
AC_CONFIG_HEADERS([src/config.h src/cysignals/cysignals_config.h])
AC_CONFIG_FILES([src/cysignals/signals.pxd])

AC_ARG_ENABLE(debug,
        AS_HELP_STRING([--enable-debug], [enable debug output]))

if test "$enable_debug" = yes; then
    AC_DEFINE([ENABLE_DEBUG_CYSIGNALS], 1, [Enable debug output])
fi

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

AC_MSG_CHECKING([whether setjmp() saves the signal mask])
AC_RUN_IFELSE([AC_LANG_PROGRAM(
    [
    #include <stdlib.h>
    #include <setjmp.h>
    #include <signal.h>
    ],
    [
    jmp_buf env;
    sigset_t set;
    sigemptyset(&set);
    if (sigprocmask(SIG_SETMASK, &set, NULL)) return 2;
    if (setjmp(env) == 0)
    {
        sigaddset(&set, SIGFPE);
        if (sigprocmask(SIG_SETMASK, &set, NULL)) return 3;
        longjmp(env, 1);
    }
    if (sigprocmask(SIG_SETMASK, NULL, &set)) return 4;
    return sigismember(&set, SIGFPE);
    ])],
    dnl YES
    [AC_MSG_RESULT([yes])]
    sigsetjmp=yes
    ,
    dnl NO
    [AC_MSG_RESULT([no])]
)

AC_MSG_CHECKING([for GNU libc])
AC_COMPILE_IFELSE([AC_LANG_SOURCE(
    [
    #include <features.h>
    #ifndef __GLIBC__
    syntax error!
    #endif
    ])],
    dnl YES
    [AC_MSG_RESULT([yes])]
    # GNU libc implements setjmp(...) as a wrapper of sigsetjmp(..., 0)
    # so we might as well call the latter directly
    sigsetjmp=yes
    ,
    dnl NO
    [AC_MSG_RESULT([no])]
)
if test x$sigsetjmp = xyes; then
    AC_DEFINE(CYSIGNALS_USE_SIGSETJMP, 1, [Define to 1 to use sigsetjmp() in sig_on(), as opposed to setjmp().])
fi


AC_OUTPUT()

dnl vim:syntax=m4
