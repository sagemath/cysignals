"""
Tests for custom signals.
"""

import time
import pytest

def test_clear_pending():
    """
    Regression test for https://github.com/sagemath/cysignals/pull/216
    """

    alarm = pytest.importorskip("cysignals.alarm")  # n/a on windows
    cypari2 = pytest.importorskip("cypari2")

    with pytest.raises(alarm.AlarmInterrupt):
        alarm.alarm(0.01)
        time.sleep(1)

    try:
        cypari2.Pari()
    except alarm.AlarmInterrupt:
        pytest.fail("AlarmInterrupt was not cleared")
