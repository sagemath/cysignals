/* Cygwin-specific implementation details */

#if defined(__CYGWIN__) && defined(__x86_64__)
#include <w32api/errhandlingapi.h>
LONG WINAPI win32_altstack_handler(EXCEPTION_POINTERS *exc)
{
    int sig = 0;
    /* Logic cribbed from Cygwin for mapping common Windows exception
     * codes to the relevant signal numbers:
     * https://cygwin.com/git/gitweb.cgi?p=newlib-cygwin.git;a=blob;f=winsup/cygwin/exceptions.cc;h=77eff05707f95f7277974fadbccf0e74223d8d1c;hb=HEAD#l650
     * Unfortunately there is no external API by which to access this
     * mapping (a la cygwin_internal(CW_GET_ERRNO_FROM_WINERROR, ...)) */
    switch (exc->ExceptionRecord->ExceptionCode) {
        case STATUS_FLOAT_DENORMAL_OPERAND:
        case STATUS_FLOAT_DIVIDE_BY_ZERO:
        case STATUS_FLOAT_INVALID_OPERATION:
        case STATUS_FLOAT_STACK_CHECK:
        case STATUS_FLOAT_INEXACT_RESULT:
        case STATUS_FLOAT_OVERFLOW:
        case STATUS_FLOAT_UNDERFLOW:
        case STATUS_INTEGER_DIVIDE_BY_ZERO:
        case STATUS_INTEGER_OVERFLOW:
            sig = SIGFPE;
            break;
        case STATUS_ILLEGAL_INSTRUCTION:
        case STATUS_PRIVILEGED_INSTRUCTION:
        case STATUS_NONCONTINUABLE_EXCEPTION:
            sig = SIGILL;
            break;
        case STATUS_TIMEOUT:
            sig = SIGALRM;
            break;
        case STATUS_GUARD_PAGE_VIOLATION:
        case STATUS_DATATYPE_MISALIGNMENT:
            sig = SIGBUS;
            break;
        case STATUS_ACCESS_VIOLATION:
            /* In the case of this last resort exception handling we can
             * probably safely assume this should be a SIGSEGV;
             * other access violations would have already been handled by
             * Cygwin before we wound up on the alternate stack */
        case STATUS_STACK_OVERFLOW:
        case STATUS_ARRAY_BOUNDS_EXCEEDED:
        case STATUS_IN_PAGE_ERROR:
        case STATUS_NO_MEMORY:
        case STATUS_INVALID_DISPOSITION:
            sig = SIGSEGV;
            break;
        case STATUS_CONTROL_C_EXIT:
            sig = SIGINT;
            break;
    }

    sigdie_for_sig(sig, 1);
    return ExceptionContinueExecution;
}


static void cygwin_setup_alt_stack() {
    AddVectoredContinueHandler(0, win32_altstack_handler);
}

#endif  /* CYGWIN && __x86_64__ */
