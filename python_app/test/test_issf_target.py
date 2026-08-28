import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from stasys_app.base import calculate_issf_score, TARGET_SPECS

def test_issf_scoring_center():
    """Test that center shot gets 10.9"""
    spec = TARGET_SPECS['10m_air_pistol']
    result, ring = calculate_issf_score(0, 0, spec)
    assert result == 10.9, f"Expected 10.9, got {result}"
    assert ring == 10, f"Expected ring 10, got {ring}"

def test_issf_scoring_inner_ten_edge():
    """Test at the boundary between inner-ten and outer 10-ring (2.875mm radius)"""
    spec = TARGET_SPECS['10m_air_pistol']
    # At exactly 2.875mm (0.2875 cm), it should be in the 10-ring (not inner-ten zone)
    result, ring = calculate_issf_score(0.2875, 0, spec)
    assert result == 10.0, f"Expected 10.0, got {result}"
    assert ring == 10, f"Expected ring 10, got {ring}"

def test_issf_scoring_inside_inner_ten():
    """Test just inside the inner-ten zone"""
    spec = TARGET_SPECS['10m_air_pistol']
    # Just inside inner-ten zone (2.5mm = 0.25cm < 2.875mm)
    result, ring = calculate_issf_score(0.25, 0, spec)
    # Should be slightly above 10.0
    assert 10.0 < result < 10.5, f"Expected between 10.0 and 10.5, got {result}"
    assert ring == 10, f"Expected ring 10, got {ring}"

def test_issf_scoring_miss():
    """Test that shot outside target is a miss"""
    spec = TARGET_SPECS['10m_air_pistol']
    result, ring = calculate_issf_score(9.0, 9.0, spec)
    assert result == 0.0, f"Expected 0.0 for miss, got {result}"
    assert ring == 0, f"Expected ring 0 for miss, got {ring}"

def test_issf_scoring_25m_target():
    """Test scoring with 25m target (different dimensions)"""
    spec = TARGET_SPECS['25m_sport_pistol']
    # Center should still be 10.9
    result, ring = calculate_issf_score(0, 0, spec)
    assert result == 10.9, f"Expected 10.9, got {result}"

if __name__ == '__main__':
    test_issf_scoring_center()
    test_issf_scoring_inner_ten_edge()
    test_issf_scoring_inside_inner_ten()
    test_issf_scoring_miss()
    test_issf_scoring_25m_target()
    print("All tests passed!")
