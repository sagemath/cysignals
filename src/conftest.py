import pathlib
import platform
import sys

from _pytest.nodes import Collector
from _pytest.doctest import DoctestModule

from _pytest.pathlib import resolve_pkg_root_and_module_name
import importlib

# cysignals-CSI only works from  gdb, i.e. invoke ./testgdb.py directly
collect_ignore = ["cysignals/cysignals-CSI-helper.py"]

if platform.system() == "Windows":
    collect_ignore += [
        "cysignals/alarm.pyx",
        "cysignals/pselect.pyx",
        "cysignals/pysignals.pyx",
        "cysignals/tests.pyx",
    ]

# Python 3.14+ changed the default multiprocessing start method to 'forkserver'
# on Linux, which breaks SIGCHLD-based tests. Set it back to 'fork' for compatibility.
if sys.version_info >= (3, 14) and platform.system() != "Windows":
    import multiprocessing
    try:
        multiprocessing.set_start_method('fork', force=True)
    except RuntimeError:
        # Method may already be set
        pass


def pytest_collect_file(
    file_path: pathlib.Path,
    parent: Collector,
):
    """Collect doctests in cython files and run them as test modules."""
    config = parent.config
    if file_path.suffix == ".pyx":
        if config.option.doctestmodules:
            # import the module so it's available to pytest
            _, module_name = resolve_pkg_root_and_module_name(file_path)
            module = importlib.import_module(module_name)
            # delete __test__ injected by cython, to avoid duplicate tests
            if hasattr(module, '__test__'):
                del module.__test__
            return DoctestModule.from_parent(parent, path=file_path)
    return None
