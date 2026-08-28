#!/usr/bin/env python3
"""STASYS receiver entry point and backward-compatible public façade."""

import sys

try:
    from .core import *  # noqa: F401,F403 - preserve the historical SL API
    from .core import MainWindow, ConnectionScreen, setup_database
except ImportError:  # Support `python python_app/stasys_app/SL.py` from the repo root.
    from core import *  # type: ignore # noqa: F401,F403
    from core import MainWindow, ConnectionScreen, setup_database  # type: ignore


if __name__ == '__main__':
    setup_database()
    app = QApplication(sys.argv)
    conn = ConnectionScreen()
    if conn.exec_() != QDialog.Accepted:
        sys.exit(0)
    win = MainWindow(conn.serial_port)
    if conn.is_simulation:
        win.setWindowTitle(win.windowTitle() + " [SIMULATION]")
    win.show()
    sys.exit(app.exec_())
