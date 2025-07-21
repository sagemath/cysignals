project('cysignals', 'c', 'cpp', 'cython',
  default_options: ['warning_level=2', 'cpp_std=c++17']
)

# Python
py_module = import('python')
py = py_module.find_installation(pure: false)
py_dep = py.dependency()

# Compilers
cc = meson.get_compiler('c')
cxx = meson.get_compiler('cpp')

is_windows = host_machine.system() == 'windows'
is_cygwin = host_machine.system() == 'cygwin'
is_msvc = cc.get_id() == 'msvc'
is_mingw = cc.get_id()=='gcc' and host_machine.system()=='windows'

# Set preprocessor macros
# Disable .c line numbers in exception tracebacks
add_project_arguments('-DCYTHON_CLINE_IN_TRACEBACK=0', language: 'c')
# Disable sanity checking in GNU libc
# This is required because of false positives in the longjmp() check
add_project_arguments('-U_FORTIFY_SOURCE', language: 'c')

# Platform-specific settings
if is_cygwin
  # On Cygwin FD_SETSIZE defaults to a rather low 64; we set it higher for use with PSelecter
  # See https://github.com/sagemath/cysignals/pull/57
  add_project_arguments('-DFD_SETSIZE=512', language: 'c')
endif

config = configuration_data()
# Toggle debug output
config.set('ENABLE_DEBUG_CYSIGNALS', get_option('debug') ? 1 : 0)

config.set('HAVE_EXECINFO_H', cc.has_header('execinfo.h') ? 1 : 0)
config.set('HAVE_SYS_MMAN_H', cc.has_header('sys/mman.h') ? 1 : 0)
config.set('HAVE_SYS_PRCTL_H', cc.has_header('sys/prctl.h') ? 1 : 0)
config.set('HAVE_TIME_H', cc.has_header('time.h') ? 1 : 0)
config.set('HAVE_SYS_WAIT_H', cc.has_header('sys/wait.h') ? 1 : 0)
config.set('HAVE_WINDOWS_H', cc.has_header('windows.h') ? 1 : 0)

config.set('HAVE_FORK', (cc.has_function('fork') and not is_mingw) ? 1 : 0)
config.set('HAVE_KILL', cc.has_function('kill') ? 1 : 0)
config.set('HAVE_SIGPROCMASK', cc.has_function('sigprocmask') ? 1 : 0)
config.set('HAVE_SIGALTSTACK', cc.has_function('sigaltstack') ? 1 : 0)
config.set('HAVE_BACKTRACE', cc.has_function('backtrace') ? 1 : 0)

# We add the "leal" instruction to reduce false positives in case some
# non-x86 architecture also has an "emms" instruction.
config.set('HAVE_EMMS', cc.links('int main() { asm("leal (%eax), %eax; emms"); return 0; }') ? 1 : 0)

# Whether setjmp() saves the signal mask
setjmp_saves_mask = cc.links('''
#include <stdlib.h>
#include <setjmp.h>
#include <signal.h>
jmp_buf env;
sigset_t set;
int main() {
    sigemptyset(&set);
    if (sigprocmask(SIG_SETMASK, &set, NULL)) return 2;
    if (setjmp(env) == 0) {
        sigaddset(&set, SIGFPE);
        if (sigprocmask(SIG_SETMASK, &set, NULL)) return 3;
        longjmp(env, 1);
    }
    if (sigprocmask(SIG_SETMASK, NULL, &set)) return 4;
    return sigismember(&set, SIGFPE);
}
''')
gnulibc = cc.links('''
  #include <features.h>
  #ifndef __GLIBC__
  syntax error!
  #endif
  int main() { return 0; }
''')
# Define to 1 to use sigsetjmp() in sig_on(), as opposed to setjmp().
config.set('CYSIGNALS_USE_SIGSETJMP', (setjmp_saves_mask or gnulibc) ? 1 : 0)

# Check for atomic operations
# for _Atomic in C code
config.set('CYSIGNALS_C_ATOMIC', cc.links('int main(void) { static _Atomic int x; return 0; }') ? 1 : 0)
# for _Atomic with OpenMP in C code
config.set('CYSIGNALS_C_ATOMIC_WITH_OPENMP', cc.links('int main(void) { static _Atomic int x; return 0; }', args: ['-fopenmp']) ? 1 : 0)
# for _Atomic in C++ code
config.set('CYSIGNALS_CXX_ATOMIC', cxx.links('int main() { static _Atomic int x; return 0; }') ? 1 : 0)
# for _Atomic with OpenMP in C++ code
config.set('CYSIGNALS_CXX_ATOMIC_WITH_OPENMP', cxx.links('int main() { static _Atomic int x; return 0; }', args: ['-fopenmp']) ? 1 : 0)
# for std::atomic in C++ code
config.set('CYSIGNALS_STD_ATOMIC', cxx.links('#include <atomic>\nint main() { static std::atomic<int> x; return 0; }') ? 1 : 0)
# for std::atomic with OpenMP in C++ code
config.set('CYSIGNALS_STD_ATOMIC_WITH_OPENMP', cxx.links('#include <atomic>\nint main() { static std::atomic<int> x; return 0; }', args: ['-fopenmp']) ? 1 : 0)

if is_windows
  threads_dep = []
else
  threads_dep = dependency('threads')
endif

subdir('src')

pytest = py_module.find_installation(modules: ['pytest'], required: false)
if pytest.found()
  test('pytest', pytest, args: ['-m', 'pytest'], workdir: meson.current_source_dir(), timeout: 300, verbose: true, is_parallel: false)
else
  message('pytest not found, skipping tests')
endif

build = py_module.find_installation(modules: ['build'], required: false)
if build.found()
  test('example', py, args: ['-m', 'build', '--no-isolation', 'example'], workdir: meson.current_source_dir())
else
  message('build not found, skipping example')
endif
