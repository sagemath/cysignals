cdef extern from "pxi_warning.h": pass

from cysignals.signals cimport *
from cysignals.memory cimport (
        sig_malloc, sig_realloc, sig_calloc, sig_free,
        check_allocarray, check_reallocarray,
        check_malloc, check_realloc, check_calloc)
