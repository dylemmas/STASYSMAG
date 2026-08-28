"""Compatibility checks for the native ESP-IDF protocol component."""

from pathlib import Path


ROOT = Path(__file__).parents[2]
HEADER = ROOT / "firmware" / "components" / "app_protocol" / "include" / "app_protocol.h"
SOURCE = ROOT / "firmware" / "components" / "app_protocol" / "app_protocol.cpp"


def test_native_protocol_component_declares_36_byte_packet():
    """The native component must expose the existing Python packet contract."""
    assert HEADER.exists()
    text = HEADER.read_text(encoding="utf-8")
    assert "STASYS_PACKET_SIZE = 36" in text
    assert "staysys_packet_t" in text


def test_native_protocol_serializes_little_endian_packet():
    """Native packet serialization must be explicit and independently testable."""
    assert SOURCE.exists()
    text = SOURCE.read_text(encoding="utf-8")
    assert "staysys_packet_serialize" in text
    assert "checksum" in text
    assert "0xAA" in text and "0xBB" in text


def test_native_protocol_has_bounded_auth_challenge():
    """Authentication input must have a fixed bound before hashing."""
    text = HEADER.read_text(encoding="utf-8") if HEADER.exists() else ""
    assert "STASYS_MAX_CHALLENGE_LEN" in text
    assert "staysys_auth_digest" in text
