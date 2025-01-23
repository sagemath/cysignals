import pathlib
import platform

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
            del module.__test__
            return DoctestModule.from_parent(parent, path=file_path)
    return None
