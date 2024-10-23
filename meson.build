project('cysignals', 'c', 'cpp', 'cython', 'python',
  version: '1.0',
  license: 'LGPL-3.0-or-later',
  default_options: ['warning_level=3', 'cpp_std=c++11']
)

py3_mod = import('python').find_installation('python3')

py3_mod.extension_module('cysignals',
  sources: [
    'src/cysignals/signals.pyx',
    'src/cysignals/pysignals.pyx',
    'src/cysignals/alarm.pyx',
    'src/cysignals/pselect.pyx',
    'src/cysignals/tests.pyx'
  ],
  include_directories: ['src', 'src/cysignals'],
  install: true,
  subdir: 'cysignals'
)

py3_mod.install_sources('src/cysignals', subdir: 'cysignals')
py3_mod.install_sources('src/scripts', subdir: 'scripts')

# Add the checks and config file generation from configure.ac
cc = meson.get_compiler('c')
cxx = meson.get_compiler('cpp')

config_h = configuration_data()
config_h.set('ENABLE_DEBUG_CYSIGNALS', get_option('debug') ? 1 : 0)

config_h.set('HAVE_EXECINFO_H', cc.has_header('execinfo.h') ? 1 : 0)
config_h.set('HAVE_SYS_MMAN_H', cc.has_header('sys/mman.h') ? 1 : 0)
config_h.set('HAVE_SYS_PRCTL_H', cc.has_header('sys/prctl.h') ? 1 : 0)
config_h.set('HAVE_TIME_H', cc.has_header('time.h') ? 1 : 0)
config_h.set('HAVE_SYS_WAIT_H', cc.has_header('sys/wait.h') ? 1 : 0)
config_h.set('HAVE_WINDOWS_H', cc.has_header('windows.h') ? 1 : 0)

config_h.set('HAVE_FORK', cc.has_function('fork') ? 1 : 0)
config_h.set('HAVE_KILL', cc.has_function('kill') ? 1 : 0)
config_h.set('HAVE_SIGPROCMASK', cc.has_function('sigprocmask') ? 1 : 0)
config_h.set('HAVE_SIGALTSTACK', cc.has_function('sigaltstack') ? 1 : 0)
config_h.set('HAVE_BACKTRACE', cc.has_function('backtrace') ? 1 : 0)

config_h.set('HAVE_EMMS', cc.links('int main() { asm("leal (%eax), %eax; emms"); return 0; }') ? 1 : 0)

config_h.set('CYSIGNALS_USE_SIGSETJMP', cc.links('''
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
''') ? 1 : 0)

config_h.set('CYSIGNALS_C_ATOMIC', cc.links('static _Atomic int x;') ? 1 : 0)
config_h.set('CYSIGNALS_C_ATOMIC_WITH_OPENMP', cc.links('static _Atomic int x;', args: ['-fopenmp']) ? 1 : 0)

config_h.set('CYSIGNALS_CXX_ATOMIC', cxx.links('static _Atomic int x;') ? 1 : 0)
config_h.set('CYSIGNALS_CXX_ATOMIC_WITH_OPENMP', cxx.links('static _Atomic int x;', args: ['-fopenmp']) ? 1 : 0)

config_h.set('CYSIGNALS_STD_ATOMIC', cxx.links('#include <atomic>\nstatic std::atomic<int> x;') ? 1 : 0)
config_h.set('CYSIGNALS_STD_ATOMIC_WITH_OPENMP', cxx.links('#include <atomic>\nstatic std::atomic<int> x;', args: ['-fopenmp']) ? 1 : 0)

config_h.set('MINSIGSTKSZ_IS_CONSTANT', cc.links('''
#include <signal.h>
static char alt_stack[MINSIGSTKSZ];
int main() { return 0; }
''') ? 1 : 0)

configure_file(output: 'src/config.h', configuration: config_h)
configure_file(output: 'src/cysignals/cysignals_config.h', configuration: config_h)
configure_file(output: 'src/cysignals/signals.pxd', configuration: config_h)
