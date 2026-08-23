"""Tests for Feinwerkbau profile defaults and UI configuration."""

from stasys_app.SL import FEINWERKBAU_PROFILES, get_feinwerkbau_profile


def test_profiles_include_pistol_and_rifle_defaults():
    assert "FWB_P700" in FEINWERKBAU_PROFILES
    assert "FWB_P800" in FEINWERKBAU_PROFILES
    assert "FWB_700_RIFLE" in FEINWERKBAU_PROFILES
    assert FEINWERKBAU_PROFILES["FWB_P700"]["type"] == "pistol"
    assert FEINWERKBAU_PROFILES["FWB_700_RIFLE"]["type"] == "rifle"


def test_profile_lookup_returns_safe_default_for_unknown_profile():
    profile = get_feinwerkbau_profile("not-a-profile")
    assert profile["id"] == "FWB_P800"
    assert profile["target_type"] == "10m_air_pistol"
