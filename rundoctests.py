#!/usr/bin/env python
#
# Run doctests for cysignals
#
# We add the ELLIPSIS flag by default and we run all tests even if
# one fails.
#
from __future__ import print_function

import os
import sys
import doctest
from doctest import DocTestParser, Example, SKIP
from multiprocessing import Process

flags = doctest.ELLIPSIS
timeout = 600

filenames = sys.argv[1:]
if os.name == 'nt':
    notinwindows = set(['src/cysignals/pysignals.pyx',
                        'src/cysignals/alarm.pyx',
                        'src/cysignals/pselect.pyx'])

    filenames = [f for f in filenames if f not in notinwindows]


# Add an option to flag doctests which should be skipped depending on
# the platform
SKIP_WINDOWS = doctest.register_optionflag("SKIP_WINDOWS")
SKIP_CYGWIN = doctest.register_optionflag("SKIP_CYGWIN")
SKIP_POSIX = doctest.register_optionflag("SKIP_POSIX")

skipflags = set()

if os.name == 'posix':
    skipflags.add(SKIP_POSIX)
elif os.name == 'nt':
    skipflags.add(SKIP_WINDOWS)
if sys.platform == 'cygwin':
    skipflags.add(SKIP_CYGWIN)


class CysignalsDocTestParser(DocTestParser):
    def parse(self, *args, **kwargs):
        examples = DocTestParser.parse(self, *args, **kwargs)
        for example in examples:
            if not isinstance(example, Example):
                continue
            if any(flag in example.options for flag in skipflags):
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
    import resource
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
    except BaseException as E:
        print(E)
    finally:
        os._exit(23)


if __name__ == "__main__":
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
            print("Doctest {} terminated. Timeout limit exceeded "
                  "(>{}s)".format(f, timeout), file=sys.stderr)
            success = False
        elif status != 0:
            success = False
            if status < 0:
                print("killed by signal: {}".format(abs(status)), file=sys.stderr)
            elif status != 23:
                print("bad exit: {}".format(status), file=sys.stderr)

    sys.exit(0 if success else 1)
