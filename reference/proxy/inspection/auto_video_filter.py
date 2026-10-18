"""Temporary per-iPhone target derived from YouTube navigation requests."""
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

STATE_PATH = Path(__file__).resolve().parent / 'auto-video-state.json'


class AutoSelector:
    def __init__(self, state_path=STATE_PATH, clock=time.time):
        self.state_path = state_path
        self.clock = clock
        self.states = {}

    def consider(self, client, navigation, window_seconds, request_id):
        if not client or not navigation or not navigation.get('eligible'):
            return None
        now = self.clock()
        old = self.states.get(client, {})
        if old.get('videoId') == navigation['videoId'] and old.get('expiresAtEpoch', 0) > now:
            return None  # Retries must not extend the window indefinitely.
        state = {'clientIp': client, 'videoId': navigation['videoId'],
                 'detectedAt': datetime.fromtimestamp(now, timezone.utc).isoformat(),
                 'expiresAtEpoch': now + window_seconds, 'windowSeconds': window_seconds,
                 'source': navigation['source'], 'requestId': request_id,
                 'transport': 'onesie' if navigation.get('onesieStatus') == 'decoded' else 'api'}
        self.states[client] = state
        self.save()
        return state

    def active(self, client):
        state = self.states.get(client)
        return state if state and state['expiresAtEpoch'] > self.clock() else None

    def save(self):
        temporary = self.state_path.with_suffix('.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as handle:
            json.dump(self.states, handle, ensure_ascii=False)
        os.replace(temporary, self.state_path)


selector = AutoSelector()
