#*****************************************************************************
#  cysignals is free software: you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published
#  by the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  cysignals is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with cysignals.  If not, see <http://www.gnu.org/licenses/>.
#
#*****************************************************************************

# Auto-generated file setting the correct include directories
cimport cysignals.__init__
from libc.signal cimport sig_atomic_t

cdef extern from "struct_signals.h":
    ctypedef struct cysigs_t:
        sig_atomic_t sig_on_count
        const char* s

cdef extern from "macros.h" nogil:
    int sig_on() except 0
    int sig_str(char*) except 0
    int sig_check() except 0
    void sig_off()
    void sig_retry()  # Does not return
    void sig_error()  # Does not return
    void sig_block()
    void sig_unblock()

    # Macros behaving exactly like sig_on, sig_str and sig_check but
    # which are *not* declared "except 0".  This is useful if some
    # low-level Cython code wants to do its own exception handling.
    int sig_on_no_except "sig_on"()
    int sig_str_no_except "sig_str"(char*)
    int sig_check_no_except "sig_check"()


# This function does nothing, but it is declared cdef except *, so it
# can be used to make Cython check whether there is a pending exception
# (PyErr_Occurred() is non-NULL). To Cython, it will look like
# cython_check_exception() actually raised the exception.
cdef inline void cython_check_exception() nogil except *:
    pass


# Private stuff below, should not be used directly
cdef nogil:
    cysigs_t cysigs
    void _sig_on_interrupt_received()
    void _sig_on_recover()
    void _sig_off_warning(const char*, int)
    void print_backtrace()

    inline cysigs_t* get_cysigs "get_cysigs"():
        return &cysigs
    inline void call_sig_on_interrupt_received "call_sig_on_interrupt_received"():
        _sig_on_interrupt_received()
    inline void call_sig_on_recover "call_sig_on_recover"():
        _sig_on_recover()
    inline void call_sig_off_warning "call_sig_off_warning"(const char* f, int n):
        _sig_off_warning(f, n)
