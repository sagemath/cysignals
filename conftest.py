import pathlib

from _pytest.nodes import Collector
from _pytest.doctest import DoctestModule

collect_ignore = ["src/scripts/cysignals-CSI-helper.py"]

"""Collect doctests in cython files and run them as test modules."""
def pytest_collect_file(
    file_path: pathlib.Path,
    parent: Collector,
) -> DoctestModule | None:
    config = parent.config
    if file_path.suffix == ".pyx":
        if config.option.doctestmodules:
            return DoctestModule.from_parent(parent, path=file_path)
    return None
