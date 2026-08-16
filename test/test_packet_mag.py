"""Tests for the 36-byte packet format with magnetometer fields."""

import os
import sys
import struct

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'stasys_app'))
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')

from base import (
    PACKET_SIZE,
    PACKET_FORMAT,
    PACKET_PAYLOAD_SIZE,
    PACKET_HEADER,
    MAG_GAIN_LSB_PER_GA,
)


def test_packet_format_size_is_36():
    """Total packet must be 36 bytes: 2 header + 33 payload + 1 checksum."""
    assert PACKET_SIZE == 36
    assert PACKET_PAYLOAD_SIZE == 33
    assert len(PACKET_HEADER) == 2


def test_packet_format_fields():
    """Format string must have 11 fields: 6 floats + 3 shorts + 1 ushort + 1 byte."""
    count = PACKET_FORMAT.count('f') + PACKET_FORMAT.count('h') + \
            PACKET_FORMAT.count('H') + PACKET_FORMAT.count('B')
    assert count == 11, f"Expected 11 fields, got {count}"


def test_struct_pack_matches_format():
    """Packing and unpacking must round-trip correctly."""
    sample = (1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 100, 200, 300, 5000, 80)
    packed = struct.pack(PACKET_FORMAT, *sample)
    assert len(packed) == PACKET_PAYLOAD_SIZE
    unpacked = struct.unpack(PACKET_FORMAT, packed)
    assert unpacked == sample


def test_total_packet_size():
    """Total packet = 2 header + 33 payload + 1 checksum = 36 bytes."""
    assert PACKET_SIZE == 36
    assert PACKET_PAYLOAD_SIZE == 33  # payload bytes (before checksum)
    assert PACKET_HEADER == b'\xAA\xBB'


def test_mock_serial_packet_size():
    """MockSerial produces 36-byte packets (call twice — first initializes timer)."""
    import time as _time
    from base import MockSerial
    mock = MockSerial()
    mock.update_sim()
    _time.sleep(0.02)  # wait past DT
    mock.update_sim()
    assert mock.in_waiting == PACKET_SIZE
    header = mock.buffer[:2]
    assert header == PACKET_HEADER
    payload = mock.buffer[2:-1]
    assert len(payload) == PACKET_PAYLOAD_SIZE
    checksum = mock.buffer[-1]
    # Verify checksum
    calc = 0
    for b in payload:
        calc ^= b
    assert checksum == calc


def test_parse_rejects_30_byte_packet():
    """Old 30-byte packets should not unpack to 11 fields."""
    old_format = '<ffffffHB'
    old_sample = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 80)
    old_payload = struct.pack(old_format, *old_sample)
    assert len(old_payload) == 27
    # Try unpacking with new format — should fail (wrong number of fields)
    try:
        struct.unpack(PACKET_FORMAT, old_payload + b'\x00\x00\x00')
        assert False, "Should have raised error"
    except struct.error:
        pass  # Expected


def test_mag_fields_are_int16_range():
    """Mag values must fit in int16 (-32768 to 32767)."""
    max_raw = int(1.3 * MAG_GAIN_LSB_PER_GA)
    assert max_raw < 32767, f"Mag raw {max_raw} exceeds int16 range"
    sample = (0.0, 0.0, 9.81, 0.0, 0.0, 0.0, -32767, 32767, 0, 0, 80)
    packed = struct.pack(PACKET_FORMAT, *sample)
    unpacked = struct.unpack(PACKET_FORMAT, packed)
    assert unpacked[6] == -32767
    assert unpacked[7] == 32767
