import sys

import pytest


def pytest_configure(config):
    # Initial setup for cysignals tests

    # For doctests, we want exceptions to look the same,
    # regardless of the Python version. Python 3 will put the
    # module name in the traceback, which we avoid by faking
    # the module to be __main__.
    from cysignals.signals import AlarmInterrupt, SignalError
    for typ in [AlarmInterrupt, SignalError]:
        typ.__module__ = "__main__"

    import resource
    # Limit stack size to avoid errors in stack overflow doctest
    stacksize = 1 << 20
    resource.setrlimit(resource.RLIMIT_STACK, (stacksize, stacksize))

    # Disable core dumps
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

    if sys.platform == 'darwin':
        from cysignals.signals import _setup_alt_stack
        _setup_alt_stack()
