from signal_pyx.signals cimport *

cdef extern from 'pxi.h':
    int import_signal_pyx__signals() except -1

# This *must* be done for every module using interrupt functions
# otherwise you will get segmentation faults.
import_signal_pyx__signals()
