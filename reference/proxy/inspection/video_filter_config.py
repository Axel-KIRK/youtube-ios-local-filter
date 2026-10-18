"""Configuration locale atomique, partagée par le proxy et le tableau de bord."""
import json
import os
import re
from pathlib import Path

CONFIG_PATH = Path(__file__).resolve().parent / 'video-filter.json'


def read_config():
    try:
        value = json.loads(CONFIG_PATH.read_text())
        if type(value.get('enabled')) is not bool or not re.fullmatch(r'[A-Za-z0-9_-]{11}', value.get('videoId', '')):
            raise ValueError('Configuration invalide')
        value.setdefault('mode', 'manual')
        value.setdefault('windowSeconds', 45)
        if value['mode'] not in ('manual', 'auto') or type(value['windowSeconds']) is not int or not 10 <= value['windowSeconds'] <= 120:
            raise ValueError('Mode ou durée invalide')
        return value
    except FileNotFoundError:
        return {'enabled': False, 'videoId': 'hw2iFtnTygA'}
    except (ValueError, TypeError, AttributeError, OSError):
        # Une configuration corrompue ne doit pas désactiver silencieusement un filtre.
        return {'enabled': True, 'videoId': '', 'error': 'Configuration illisible : médias bloqués'}


def write_config(enabled, video_id, mode='manual', window_seconds=45):
    if type(enabled) is not bool or not isinstance(video_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
        raise ValueError('État ou identifiant vidéo invalide')
    if mode not in ('manual', 'auto') or type(window_seconds) is not int or not 10 <= window_seconds <= 120:
        raise ValueError('Mode ou durée invalide')
    value = {'enabled': enabled, 'videoId': video_id, 'mode': mode, 'windowSeconds': window_seconds}
    temporary = CONFIG_PATH.with_suffix('.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as handle:
        json.dump(value, handle)
        handle.write('\n')
    os.replace(temporary, CONFIG_PATH)
    return value
