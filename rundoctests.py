#!/usr/bin/env python
#
# Run doctests for cysignals
#
# We add the ELLIPSIS flag by default and we run all tests even if
# one fails.
#

import os
import sys
import doctest
from doctest import DocTestParser, Example, SKIP
from multiprocessing import Process
if os.name != 'nt':
    import resource

flags = doctest.ELLIPSIS
timeout = 600

filenames = list(sys.argv[1:])
if os.name == 'nt':
    notinwindows = ['src/cysignals/pysignals.pyx',
                    'src/cysignals/alarm.pyx',
                    'src/cysignals/pselect.pyx']

    for f in list(filenames):
        if f in notinwindows:
            filenames.remove(f)

# Add an option to flag doctest what should not be run on windows.
SKIP_WINDOWS = doctest.register_optionflag("SKIP_WINDOWS")
SKIP_CYGWIN = doctest.register_optionflag("SKIP_CYGWIN")
SKIP_POSIX = doctest.register_optionflag("SKIP_POSIX")

flag_map = {
    SKIP_WINDOWS: lambda: os.name == 'nt',
    SKIP_CYGWIN: lambda: sys.platform == 'cygwin',
    SKIP_POSIX: lambda: os.name == 'posix'
}


class CysignalsDocTestParser(DocTestParser):
    def parse(self, *args, **kwargs):
        examples = DocTestParser.parse(self, *args, **kwargs)
        for example in examples:
            if not isinstance(example, Example):
                continue
            for flag, flag_test in flag_map.items():
                if flag in example.options and flag_test():
                    example.options[SKIP] = True

        return examples


parser = CysignalsDocTestParser()


print("Doctesting {} files.".format(len(filenames)))

# For doctests, we want exceptions to look the same,
# regardless of the Python version. Python 3 will put the
# module name in the traceback, which we avoid by faking
# the module to be __main__.
from cysignals.signals import AlarmInterrupt, SignalError
for typ in [AlarmInterrupt, SignalError]:
    typ.__module__ = "__main__"

if os.name != 'nt':
    # Limit stack size to avoid errors in stack overflow doctest
    stacksize = 1 << 20
    resource.setrlimit(resource.RLIMIT_STACK, (stacksize, stacksize))

    # Disable core dumps
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

def testfile(file):
    # Child process
    try:
        if sys.platform == 'darwin':
            from cysignals.signals import _setup_alt_stack
            _setup_alt_stack()
        failures, _ = doctest.testfile(file, module_relative=False, optionflags=flags, parser=parser)
        if not failures:
            os._exit(0)
    finally:
        os._exit(23)

if __name__ == "__main__": # Mandatory for windows cases.
    success = True
    for f in filenames:
        print(f)
        sys.stdout.flush()

        # Test every file in a separate process (like in SageMath) to avoid
        # side effects from doctests.
        p = Process(target=testfile, args=(f,))
        p.start()
        p.join(timeout)

        status = p.exitcode

        if p.is_alive():
            p.terminate()
            print("Doctest {} terminated. Timeout limit exceeded (>{}s)".format(f, timeout))
            success = False
        elif status != 0:
            success = False
            if os.name != 'nt':
                if os.WIFEXITED(status):
                    st = os.WEXITSTATUS(status)
                    if st != 23:
                        print("bad exit: {}".format(st))
                elif os.WIFSIGNALED(status):
                    sig = os.WTERMSIG(status)
                    print("killed by signal: {}".format(sig))
                else:
                    print("unknown status: {}".format(status))

    sys.exit(0 if success else 1)
