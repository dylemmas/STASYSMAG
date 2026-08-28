# STASYS

STASYS is split into three independent product areas:

- `firmware/` — native ESP32 ESP-IDF/PlatformIO firmware. Build from this directory with `pio run -e esp32dev`.
- `python_app/` — supported PyQt5 receiver and its tests. Start it with `python python_app/stasys_app/SL.py`; run tests with `python -m pytest python_app/test/ -v`.
- `android_app/` — Flutter Android companion app. Run Flutter commands from this directory.

Historical Arduino sketches and the bundled legacy firmware image are kept in `firmware/legacy/`. Shared design documentation remains under `docs/` and at the repository root.
