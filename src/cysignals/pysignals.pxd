from posix.signal cimport sigaction_t

cdef class SigAction:
    cdef sigaction_t act
