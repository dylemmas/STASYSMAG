import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from PyQt5.QtWidgets import QApplication
import pytest

from base import ShotTraceCanvas
from base import ReplayBar  # will fail until Task 6b creates the class


@pytest.fixture(scope='session')
def qapp():
    app = QApplication.instance() or QApplication(sys.argv)
    yield app


def test_canvas_has_replay_attributes(qapp):
    """Canvas should expose playback_pos and replay_mode after construction."""
    c = ShotTraceCanvas()
    assert hasattr(c, 'playback_pos'), "missing playback_pos"
    assert hasattr(c, 'replay_mode'), "missing replay_mode"
    assert c.playback_pos == 0
    assert c.replay_mode is False


def test_set_trace_computes_phase_boundaries(qapp):
    """After set_trace, _hold_end / _press_end / _total reflect phase lengths,
    and replay_mode is True with playback_pos reset to 0."""
    c = ShotTraceCanvas()
    hold = ([0.1 * i for i in range(150)], [0.0] * 150)
    press = ([0.0] * 30, [0.0] * 30)
    recoil = ([0.0] * 10, [0.0] * 10)
    c.set_trace(hold=hold, press=press, recoil=recoil, shot_idx=1)
    assert c._hold_end == 150
    assert c._press_end == 180
    assert c._total == 190
    assert c.playback_pos == 0
    assert c.replay_mode is True


def test_current_sample_xy_helper(qapp):
    """Helper returns the (x, y) of the sample at playback_pos."""
    c = ShotTraceCanvas()
    hold = ([0.1 * i for i in range(150)], [0.5 * i for i in range(150)])
    press = ([1.0 + 0.01 * i for i in range(30)], [2.0 + 0.02 * i for i in range(30)])
    recoil = ([5.0] * 10, [10.0] * 10)
    c.set_trace(hold=hold, press=press, recoil=recoil, shot_idx=1)

    # Sample 0: start of hold
    c.playback_pos = 0
    assert c._current_sample_xy() == (0.0, 0.0)

    # Sample 100: middle of hold
    c.playback_pos = 100
    assert c._current_sample_xy() == pytest.approx((10.0, 50.0))

    # Sample 150: start of press
    c.playback_pos = 150
    assert c._current_sample_xy() == pytest.approx((1.0, 2.0))

    # Sample 170: middle of press
    c.playback_pos = 170
    assert c._current_sample_xy() == pytest.approx((1.20, 2.40))

    # Sample 180: start of recoil
    c.playback_pos = 180
    assert c._current_sample_xy() == (5.0, 10.0)

    # At end (190): parks on the last recoil sample, not out of range
    c.playback_pos = 190
    assert c._current_sample_xy() == (5.0, 10.0)


def test_paint_event_with_replay_mode_does_not_crash(qapp):
    """Smoke test: paintEvent runs in replay mode at various positions without raising."""
    c = ShotTraceCanvas()
    c.resize(400, 400)
    hold = ([0.1 * i for i in range(150)], [0.5 * i for i in range(150)])
    press = ([1.0 + 0.01 * i for i in range(30)], [2.0 + 0.02 * i for i in range(30)])
    recoil = ([5.0] * 10, [10.0] * 10)
    c.set_trace(hold=hold, press=press, recoil=recoil, shot_idx=1)
    for pos in (0, 1, 75, 149, 150, 165, 179, 180, 185, 189, 190):
        c.playback_pos = pos
        c.repaint()  # forces paintEvent to run synchronously
    # Outside replay mode also fine
    c.replay_mode = False
    c.repaint()


def test_replay_bar_constructs_with_default_total(qapp):
    bar = ReplayBar()
    assert bar._total == 190
    assert bar._speed == 1.0
    assert bar._playing is False
    assert hasattr(bar, '_timer')
