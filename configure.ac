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
AC_ARG_WITH(pari,
    AS_HELP_STRING([--without-pari], [build without PARI support]))

if test "$enable_debug" = yes; then
    AC_DEFINE([ENABLE_DEBUG_CYSIGNALS], 1, [Enable debug output])
fi


AC_PROG_CC()
dnl We use the C compiler for C++ to emulate the Python bug
dnl https://bugs.python.org/issue1222585
CXX="$CC"
CXXFLAGS="$CFLAGS"
AC_PROG_CXX()

AC_CHECK_HEADERS([execinfo.h sys/mman.h sys/prctl.h sys/time.h sys/wait.h windows.h])
AC_CHECK_FUNCS([fork kill sigprocmask sigaltstack backtrace])


have_pari=no
if test "$with_pari" != "no"; then
    AC_SEARCH_LIBS([pari_init], [pari], [
        AC_CHECK_DECL([PARI_SIGINT_block],
            [have_pari=yes], [],
            [[#include <pari/pari.h>]])])
fi

if test "$have_pari" = "yes"; then
    AC_DEFINE([HAVE_PARI], 1, [Define to 1 if PARI is fully supported.])
elif test "$with_pari" = "yes"; then
    AC_MSG_ERROR([PARI support requested but PARI was not found])
fi

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

dnl Check for atomic operations
AC_MSG_CHECKING([for _Atomic in C code])
AC_COMPILE_IFELSE([AC_LANG_SOURCE(
    [
    static _Atomic int x;
    ])],
    dnl YES
    [AC_MSG_RESULT([yes])]
    AC_DEFINE(CYSIGNALS_C_ATOMIC, 1, [Define to 1 if your C compiler supports _Atomic.])

    AC_MSG_CHECKING([for _Atomic with OpenMP in C code])
    saved_CFLAGS="$CFLAGS"
    CFLAGS="$CFLAGS -fopenmp"
    AC_COMPILE_IFELSE([AC_LANG_SOURCE(
        [
        static _Atomic int x;
        ])],
        dnl YES
        [AC_MSG_RESULT([yes])]
        AC_DEFINE(CYSIGNALS_C_ATOMIC_WITH_OPENMP, 1, [Define to 1 if your C compiler supports _Atomic with OpenMP])
        ,
        dnl NO
        [AC_MSG_RESULT([no])]
    )
    CFLAGS="$saved_CFLAGS"
    ,
    dnl NO
    [AC_MSG_RESULT([no])]
)

AC_LANG(C++)
AC_MSG_CHECKING([for _Atomic in C++ code])
AC_COMPILE_IFELSE([AC_LANG_SOURCE(
    [
    static _Atomic int x;
    ])],
    dnl YES
    [AC_MSG_RESULT([yes])]
    AC_DEFINE(CYSIGNALS_CXX_ATOMIC, 1, [Define to 1 if your C++ compiler supports _Atomic.])

    AC_MSG_CHECKING([for _Atomic with OpenMP in C++ code])
    saved_CXXFLAGS="$CXXFLAGS"
    CXXFLAGS="$CXXFLAGS -fopenmp"
    AC_COMPILE_IFELSE([AC_LANG_SOURCE(
        [
        static _Atomic int x;
        ])],
        dnl YES
        [AC_MSG_RESULT([yes])]
        AC_DEFINE(CYSIGNALS_CXX_ATOMIC_WITH_OPENMP, 1, [Define to 1 if your C++ compiler supports _Atomic with OpenMP])
        ,
        dnl NO
        [AC_MSG_RESULT([no])]
    )
    CXXFLAGS="$saved_CXXFLAGS"
    ,
    dnl NO
    [AC_MSG_RESULT([no])]
)

AC_MSG_CHECKING([for std::atomic])
AC_COMPILE_IFELSE([AC_LANG_SOURCE(
    [
    #include <atomic>
    static std::atomic<int> x;
    ])],
    dnl YES
    [AC_MSG_RESULT([yes])]
    AC_DEFINE(CYSIGNALS_STD_ATOMIC, 1, [Define to 1 if your C++ compiler supports std::atomic.])

    AC_MSG_CHECKING([for std::atomic with OpenMP in C++ code])
    saved_CXXFLAGS="$CXXFLAGS"
    CXXFLAGS="$CXXFLAGS -fopenmp"
    AC_COMPILE_IFELSE([AC_LANG_SOURCE(
        [
        #include <atomic>
        static std::atomic<int> x;
        ])],
        dnl YES
        [AC_MSG_RESULT([yes])]
        AC_DEFINE(CYSIGNALS_STD_ATOMIC_WITH_OPENMP, 1, [Define to 1 if your C++ compiler supports std::atomic with OpenMP])
        ,
        dnl NO
        [AC_MSG_RESULT([no])]
    )
    CXXFLAGS="$saved_CXXFLAGS"
    ,
    dnl NO
    [AC_MSG_RESULT([no])]
)

AC_OUTPUT()

dnl vim:syntax=m4
