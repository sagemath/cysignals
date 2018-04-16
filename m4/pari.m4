# pari.m4 serial 2
dnl m4/pari.m4 -- M4 macro processor include script
dnl
dnl Copyright (C) 2016-2017 Jerome Benoit <jgmbenoit@rezozer.net>
dnl
dnl Based on macros by Owen Taylor, modified by:
dnl Hans Petter Jansson, 2001-04-09;
dnl Allin Cottrell, April 2003;
dnl and certainly others.
dnl
dnl Copying and distribution of this file, with or without modification, are
dnl permitted in any medium without royalty provided the copyright notice and
dnl this notice are preserved. This file is offered as-is, without any warranty.
dnl

dnl AM_PATH_PARI([MINIMUM-VERSION, [ACTION-IF-FOUND [, ACTION-IF-NOT-FOUND]]])
dnl Test for the PARI/GP library, and define PARI_CPPFLAGS, PARI_CFLAGS,
dnl PARI_LDFLAGS, PARI_LIBS, and WITH_PARI_IS_YES .
dnl
AC_DEFUN([AM_PATH_PARI],[dnl
AC_REQUIRE([AC_PROG_SED])dnl
dnl AC_REQUIRE([AM_CONDITIONAL])dnl

	AC_ARG_WITH([pari],
	[AS_HELP_STRING([--with-pari],[enable support for PARI])],
	[],[with_pari=no])

	AC_MSG_CHECKING(whether PARI is enabled)
	if test x"$with_pari" != xno ; then

		AC_MSG_RESULT(yes)

		AC_ARG_WITH([pari-prefix],
			[AS_HELP_STRING([--with-pari-prefix=PREFIX],
				[specify prefix for the installed PARI [standard search prefixes]])],
			[pari_config_prefix="$withval"],[pari_config_prefix=""])
		AC_ARG_WITH([pari-include],
			[AS_HELP_STRING([--with-pari-include=PATH],
				[specify directory for the installed PARI header file [standard search paths]])],
			[pari_config_include_prefix="$withval"],[pari_config_include_prefix=""])
		AC_ARG_WITH([pari-lib],
			[AS_HELP_STRING([--with-pari-lib=PATH],
				[specify directory for the installed PARI library [standard search paths]])],
			[pari_config_lib_prefix="$withval"],[pari_config_lib_prefix=""])

		if test "x$pari_config_include_prefix" = "x" ; then
			if test "x$pari_config_prefix" != "x" ; then
				pari_config_include_prefix="$pari_config_prefix/include"
			fi
		fi
		if test "x$pari_config_lib_prefix" = "x" ; then
			if test "x$pari_config_prefix" != "x" ; then
				pari_config_lib_prefix="$pari_config_prefix/lib"
			fi
		fi

		PARI_CPPFLAGS=
		if test "x$pari_config_include_prefix" != "x" ; then
			PARI_CPPFLAGS="-I$pari_config_include_prefix"
		fi

		PARI_LDFLAGS=
		if test "x$pari_config_lib_prefix" != "x" ; then
			PARI_LDFLAGS="-L$pari_config_lib_prefix"
		fi

		PARI_CFLAGS=""
		PARI_LIBS="-lpari"

		min_pari_version=ifelse([$1], ,2.9.0,$1)
		min_pari_version_0_0_0="$min_pari_version.0.0.0"

		min_pari_version_major=`echo $min_pari_version_0_0_0 | \
			$SED 's/\([[0-9]]*\).\([[0-9]]*\).\([[0-9]]*\)\(.*\)/\1/'`
		min_pari_version_minor=`echo $min_pari_version_0_0_0 | \
			$SED 's/\([[0-9]]*\).\([[0-9]]*\).\([[0-9]]*\)\(.*\)/\2/'`
		min_pari_version_micro=`echo $min_pari_version_0_0_0 | \
			$SED 's/\([[0-9]]*\).\([[0-9]]*\).\([[0-9]]*\)\(.*\)/\3/'`

		min_pari_dotted_version="$min_pari_version_major.$min_pari_version_minor.$min_pari_version_micro"

		AC_MSG_CHECKING(for PARI - version >= $min_pari_dotted_version )

		ac_save_CPPFLAGS="$CPPFLAGS"
		ac_save_CFLAGS="$CFLAGS"
		ac_save_LDFLAGS="$LDFLAGS"
		ac_save_LIBS="$LIBS"

		CPPFLAGS="$CPPFLAGS $PARI_CPPFLAGS"
		CFLAGS="$CFLAGS $PARI_CFLAGS"
		LDFLAGS="$LDFLAGS $PARI_LDFLAGS"
		LIBS="$LIBS $PARI_LIBS"

		rm -f conf.paritest
		AC_RUN_IFELSE([AC_LANG_SOURCE(
[[
#include <pari/pari.h>
#include <stdio.h>

#define PRINTF_MSG_ERROR_MISMATCH_HEADER_LIBRARY \
	printf("*** This likely indicates either a bad configuration or some\n"); \
	printf("*** other inconsistency in the development environment. If the\n"); \
	printf("*** expected PARI library cannot be found, it may be sufficient\n"); \
	printf("*** either to set properly the LD_LIBRARY_PATH environment variable\n"); \
	printf("*** or to configure ldconfig(8) to consider the installed location.\n"); \
	printf("*** Otherwise a bad configuration or an inconsistency in the\n"); \
	printf("*** include/library search paths may be investigated; adjustments\n"); \
	printf("*** through the use of --with-pari-(include|lib) configure option\n"); \
	printf("*** may help.\n"); \
	printf("***\n"); \
	printf("*** If an old version is installed, it may be best to remove it and to\n"); \
	printf("*** reinstall a more recent one; although modifying LD_LIBRARY_PATH\n"); \
	printf("*** may also get things to work. The latest version of PARI is always\n"); \
	printf("*** available from http://pari.math.u-bordeaux.fr/.\n"); \
	printf("***\n");

int main ()
{
	long pari_hdr_version_major = 255 & PARI_VERSION_CODE >> 16 ;
	long pari_hdr_version_minor = 255 & PARI_VERSION_CODE >> 8 ;
	long pari_hdr_version_micro = 255 & PARI_VERSION_CODE ;
	long pari_lib_version_major = 255 & paricfg_version_code >> 16 ;
	long pari_lib_version_minor = 255 & paricfg_version_code >> 8 ;
	long pari_lib_version_micro = 255 & paricfg_version_code ;
	long deduced_pari_hdr_version_code = PARI_VERSION(pari_hdr_version_major,pari_hdr_version_minor,pari_hdr_version_micro) ;
	long deduced_pari_lib_version_code = PARI_VERSION(pari_lib_version_major,pari_lib_version_minor,pari_lib_version_micro) ;
	GEN M;

	pari_init(1000000,50000);
	M = mathilbert(80);

	fclose (fopen ("conf.paritest", "w"));

#if 1
	if (
			(deduced_pari_hdr_version_code != PARI_VERSION_CODE) ||
			(deduced_pari_lib_version_code != paricfg_version_code)
		) {
		printf("\n***\n");
		printf("*** PARI version numbers cannot be computed properly.\n");
		printf("*** This likely indicates either that the code on which is based the M4 macro\n");
		printf("*** needs to be refreshed or that the installed PARI library is obsolete.\n");
		printf("*** If you have an obsolete version installed, it may be best to remove it and to\n");
		printf("*** reinstall a more recent one; otherwise, feel free to correct the involved M4 code.\n");
		printf("*** The latest version of PARI is always available from http://pari.math.u-bordeaux.fr/.\n");
		printf("***\n");
		}
	else
#endif
	if (PARI_VERSION_CODE != paricfg_version_code) {
		printf("\n***\n");
		printf("*** PARI header  version code number (%ld) and\n", PARI_VERSION_CODE );
		printf("*** PARI library version code number (%ld) do not match.\n", paricfg_version_code );
		printf("***\n");
		PRINTF_MSG_ERROR_MISMATCH_HEADER_LIBRARY
		}
	else if (
			($min_pari_version_major < pari_hdr_version_major) ||
			(
				($min_pari_version_major == pari_hdr_version_major) &&
				($min_pari_version_minor < pari_hdr_version_minor)
				) ||
			(
				($min_pari_version_major == pari_hdr_version_major) &&
				($min_pari_version_minor == pari_hdr_version_minor) &&
				($min_pari_version_micro <= pari_hdr_version_micro)
				)
		) {
		return (0);
		}
	else {
		printf("\n***\n");
		printf("*** PARI version $min_pari_dotted_version or higher is required:\n");
		printf("*** an older version of PARI (%ld.%ld.%ld) was found.\n",
			pari_hdr_version_major, pari_hdr_version_minor, pari_hdr_version_micro);
		printf("*** The latest version of PARI is always available\n");
		printf("*** from http://pari.math.u-bordeaux.fr/.\n");
		printf("***\n");
		}

	return (1);
}
]]
)],[],[no_pari=yes],[AC_MSG_WARN([$ac_n "cross compiling; assumed OK... $ac_c])])

		CPPFLAGS="$ac_save_CPPFLAGS"
		CFLAGS="$ac_save_CFLAGS"
		LDFLAGS="$ac_save_LDFLAGS"
		LIBS="$ac_save_LIBS"

		if test "x$no_pari" = "x" ; then
			AC_MSG_RESULT([yes])
			ifelse([$2], , :, [$2])
		else
			AC_MSG_RESULT([no])
			if test -f conf.paritest ; then
				:
			else
				echo "***"
				echo "*** Could not run PARI test program, checking why..."
				CPPFLAGS="$CPPFLAGS $PARI_CPPFLAGS"
				CFLAGS="$CFLAGS $PARI_CFLAGS"
				LDFLAGS="$CFLAGS $PARI_LDFLAGS"
				LIBS="$LIBS $PARI_LIBS"
			AC_LINK_IFELSE([AC_LANG_PROGRAM(
[[
#include <pari/pari.h>
#include <stdio.h>
]],
[[ return (1); ]]
)],
[
echo "***"
echo "*** The test program compiled, but did not run. This usually means"
echo "*** that the run-time linker is not finding PARI or finding the wrong"
echo "*** version of PARI. If it is not finding PARI, you'll need to set your"
echo "*** LD_LIBRARY_PATH environment variable, or configure ldconfig(8) to"
echo "*** consider the installed location."
echo "***"
echo "*** If you have an old version installed, it is best to remove it; although"
echo "*** modifying LD_LIBRARY_PATH may also get things to work. The latest version"
echo "*** of PARI is always available from http://pari.math.u-bordeaux.fr/."
echo "***"
],
[
echo "***"
echo "*** The test program failed to compile or link. See the file config.log for the"
echo "*** exact error that occurred. This usually means PARI was incorrectly installed"
echo "*** or that you have moved PARI since it was installed."
echo "***"
])

				CPPFLAGS="$ac_save_CPPFLAGS"
				CFLAGS="$ac_save_CFLAGS"
				LDFLAGS="$ac_save_LDFLAGS"
				LIBS="$ac_save_LIBS"
			fi

			PARI_CPPFLAGS=""
			PARI_CFLAGS=""
			PARI_LDFLAGS=""
			PARI_LIBS=""
			with_pari=no
			m4_default([$3],[AC_MSG_ERROR([no suitable PARI library found])])
			AC_MSG_WARN([PARI is forced to be disabled])
		fi
		rm -f conf.paritest

	else

		AC_MSG_RESULT(no)

	fi

	AC_SUBST(PARI_CPPFLAGS)
	AC_SUBST(PARI_CFLAGS)
	AC_SUBST(PARI_LDFLAGS)
	AC_SUBST(PARI_LIBS)

	AM_CONDITIONAL([WITH_PARI_IS_YES],[test x"$with_pari" != xno])

])
