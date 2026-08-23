"""Compatibility and module-boundary tests for the split package."""


def test_split_modules_export_runtime_components():
    from stasys_app.canvas import AimCanvas, ReplayBar, ShotTraceCanvas
    from stasys_app.connection import ConnectionScreen, MockSerial
    from stasys_app.database import get_all_sessions, setup_database
    from stasys_app.detector import ShotDetector
    from stasys_app.main_window import MainWindow
    from stasys_app.settings import FEINWERKBAU_PROFILES

    assert all((AimCanvas, ReplayBar, ShotTraceCanvas))
    assert all((ConnectionScreen, MockSerial, get_all_sessions, setup_database))
    assert all((ShotDetector, MainWindow))
    assert "FWB_P800" in FEINWERKBAU_PROFILES


def test_legacy_facade_reexports_split_runtime():
    from stasys_app.SL import MainWindow as legacy_main_window
    from stasys_app.main_window import MainWindow

    assert legacy_main_window is MainWindow
