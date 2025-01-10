import pytest
import time

def test_clear_pending():

    from cysignals.alarm import alarm, AlarmInterrupt

    cypari2 = pytest.importorskip("cypari2")

    with pytest.raises(AlarmInterrupt):
        alarm(0.5)
        time.sleep(1)

    try:
        cypari2.Pari()
    except AlarmInterrupt:
        pytest.fail("AlarmInterrupt was not cleared")
