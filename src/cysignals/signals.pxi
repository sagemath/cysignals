# Auto-generated file setting the correct include directories
cimport cysignals

from cysignals.signals cimport *

cdef extern from 'pxi.h':
    int import_cysignals__signals() except -1

# This *must* be done for every module using interrupt functions
# otherwise you will get segmentation faults.
import_cysignals__signals()
