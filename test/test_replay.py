import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))

os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from PyQt6.QtWidgets import QApplication
import pytest

from base import ShotTraceCanvas
from base import ReplayBar  # will fail until Task 6b creates the class
from base import (HOLD_DURATION_IDX, PRESS_DURATION_IDX, RECOIL_DURATION_IDX,
                 SHOT_PHASE_TOTAL)


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
    hold = ([0.1 * i for i in range(HOLD_DURATION_IDX)], [0.0] * HOLD_DURATION_IDX)
    press = ([0.0] * PRESS_DURATION_IDX, [0.0] * PRESS_DURATION_IDX)
    recoil = ([0.0] * RECOIL_DURATION_IDX, [0.0] * RECOIL_DURATION_IDX)
    c.set_trace(hold=hold, press=press, recoil=recoil, shot_idx=1)
    assert c._hold_end == HOLD_DURATION_IDX
    assert c._press_end == HOLD_DURATION_IDX + PRESS_DURATION_IDX
    assert c._total == SHOT_PHASE_TOTAL
    assert c.playback_pos == 0
    assert c.replay_mode is True


def test_current_sample_xy_helper(qapp):
    """Helper returns the (x, y) of the sample at playback_pos."""
    c = ShotTraceCanvas()
    hold = ([0.1 * i for i in range(HOLD_DURATION_IDX)],
            [0.5 * i for i in range(HOLD_DURATION_IDX)])
    press = ([1.0 + 0.01 * i for i in range(PRESS_DURATION_IDX)],
             [2.0 + 0.02 * i for i in range(PRESS_DURATION_IDX)])
    recoil = ([5.0] * RECOIL_DURATION_IDX, [10.0] * RECOIL_DURATION_IDX)
    c.set_trace(hold=hold, press=press, recoil=recoil, shot_idx=1)

    press_start = HOLD_DURATION_IDX
    recoil_start = HOLD_DURATION_IDX + PRESS_DURATION_IDX
    last_sample = SHOT_PHASE_TOTAL - 1

    # Sample 0: start of hold
    c.playback_pos = 0
    assert c._current_sample_xy() == (0.0, 0.0)

    # Mid-hold: sample at HOLD_DURATION_IDX // 2
    c.playback_pos = HOLD_DURATION_IDX // 2
    expected_mid_x = 0.1 * (HOLD_DURATION_IDX // 2)
    expected_mid_y = 0.5 * (HOLD_DURATION_IDX // 2)
    assert c._current_sample_xy() == pytest.approx((expected_mid_x, expected_mid_y))

    # Start of press
    c.playback_pos = press_start
    assert c._current_sample_xy() == pytest.approx((1.0, 2.0))

    # Middle of press
    c.playback_pos = press_start + PRESS_DURATION_IDX // 2
    expected_x = 1.0 + 0.01 * (PRESS_DURATION_IDX // 2)
    expected_y = 2.0 + 0.02 * (PRESS_DURATION_IDX // 2)
    assert c._current_sample_xy() == pytest.approx((expected_x, expected_y))

    # Start of recoil
    c.playback_pos = recoil_start
    assert c._current_sample_xy() == (5.0, 10.0)

    # At end: parks on the last recoil sample, not out of range
    c.playback_pos = last_sample
    assert c._current_sample_xy() == (5.0, 10.0)


def test_paint_event_with_replay_mode_does_not_crash(qapp):
    """Smoke test: paintEvent runs in replay mode at various positions without raising."""
    c = ShotTraceCanvas()
    c.resize(400, 400)
    hold = ([0.1 * i for i in range(HOLD_DURATION_IDX)],
            [0.5 * i for i in range(HOLD_DURATION_IDX)])
    press = ([1.0 + 0.01 * i for i in range(PRESS_DURATION_IDX)],
             [2.0 + 0.02 * i for i in range(PRESS_DURATION_IDX)])
    recoil = ([5.0] * RECOIL_DURATION_IDX, [10.0] * RECOIL_DURATION_IDX)
    c.set_trace(hold=hold, press=press, recoil=recoil, shot_idx=1)
    last = SHOT_PHASE_TOTAL - 1
    half_hold = HOLD_DURATION_IDX // 2
    last_hold = HOLD_DURATION_IDX - 1
    press_mid = HOLD_DURATION_IDX + PRESS_DURATION_IDX // 2
    recoil_start = HOLD_DURATION_IDX + PRESS_DURATION_IDX
    for pos in (0, 1, half_hold, last_hold,
                HOLD_DURATION_IDX, press_mid, recoil_start - 1,
                recoil_start, recoil_start + RECOIL_DURATION_IDX // 2,
                last):
        c.playback_pos = pos
        c.repaint()  # forces paintEvent to run synchronously
    # Outside replay mode also fine
    c.replay_mode = False
    c.repaint()


def test_replay_bar_constructs_with_default_total(qapp):
    bar = ReplayBar()
    assert bar._total == SHOT_PHASE_TOTAL
    assert bar._playing is False
    assert hasattr(bar, '_timer')
