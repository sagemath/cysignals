import pathlib

from _pytest.nodes import Collector
from _pytest.doctest import DoctestModule

collect_ignore = ["src/scripts/cysignals-CSI-helper.py"]


def pytest_collect_file(
    file_path: pathlib.Path,
    parent: Collector,
) -> DoctestModule | None:
    """Collect doctests in cython files and run them as test modules."""
    config = parent.config
    if file_path.suffix == ".pyx":
        if config.option.doctestmodules:
            return DoctestModule.from_parent(parent, path=file_path)
    return None


# Need to import cysignals to initialize it
import cysignals
