"""Settings persistence and Feinwerkbau profiles."""

import json
import logging
from pathlib import Path
from .constants import FEINWERKBAU_PROFILES

LOGGER = logging.getLogger(__name__)
SETTINGS_FILE = Path(__file__).with_name('settings.json')

def get_feinwerkbau_profile(profile_id: str) -> dict:
    return dict(FEINWERKBAU_PROFILES.get(profile_id, FEINWERKBAU_PROFILES['FWB_P800']))

def save_settings(settings_dict: dict) -> None:
    try:
        SETTINGS_FILE.write_text(json.dumps(settings_dict, indent=4), encoding='utf-8')
    except OSError as exc:
        LOGGER.error('Failed to save settings: %s', exc)

def load_settings() -> dict:
    try:
        return json.loads(SETTINGS_FILE.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return {}
