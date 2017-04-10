# This file is kept for backwards compatibility only, you should no
# longer use this .pxi file.

from cysignals.signals cimport *
from cysignals.memory cimport (
        sig_malloc, sig_realloc, sig_calloc, sig_free,
        check_allocarray, check_reallocarray,
        check_malloc, check_realloc, check_calloc)
