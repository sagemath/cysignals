from cysignals.signals cimport sig_check
from cysignals.memory cimport check_allocarray


def recip_sum(long count):
    cdef double s = 0
    cdef long i
    for i in range(1, count + 1):
        sig_check()
        s += 1 / <double>i
    return s


cdef long* safe_range_long(long count) except? NULL:
    """
    This function can be safely called within a sig_on block.

    With an ordinary malloc, this is not the case since the internal
    state of the heap would be messed up if an interrupt happens during
    malloc().
    """
    cdef long* a = <long*>check_allocarray(count, sizeof(long))
    for i in range(count):
        a[i] = i
    return a
