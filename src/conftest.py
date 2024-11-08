import pathlib

from _pytest.nodes import Collector
from _pytest.doctest import DoctestModule


def pytest_collect_file(
    file_path: pathlib.Path,
    parent: Collector,
):
    """Collect doctests in cython files and run them as test modules."""
    config = parent.config
    if file_path.suffix == ".pyx":
        if config.option.doctestmodules:
            return DoctestModule.from_parent(parent, path=file_path)
    return None


# Need to import cysignals to initialize it
import cysignals  # noqa: E402

try:
    import cysignals.alarm
except ImportError:
    pass
try:
    import cysignals.signals
except ImportError:
    pass
try:
    import cysignals.pselect
except ImportError:
    pass
try:
    import cysignals.pysignals
except ImportError:
    pass
try:
    import cysignals.tests  # noqa: F401
except ImportError:
    pass
