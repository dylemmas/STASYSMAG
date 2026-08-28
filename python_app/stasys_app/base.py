"""Backward-compatible exports for the STASYS receiver implementation.

Tests and legacy tooling historically imported from a `base` module that lived
next to `SL.py`. Keep that surface working: when imported as part of the
`stasys_app` package, re-export `core`; when imported top-level (tests insert
`stasys_app/` on `sys.path`), fall back to a plain import.
"""

try:
    from .core import *  # noqa: F401,F403
except ImportError:  # Imported as a top-level module (sys.path includes stasys_app/).
    from core import *  # type: ignore # noqa: F401,F403
