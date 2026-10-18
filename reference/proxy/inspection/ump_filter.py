"""Local UMP filter: only media associated with target_id is forwarded.

Each block prefix is held until its decision. Large allowed media is then
streamed without storage; other media is consumed. Header mappings are
scoped to each HTTP response."""
import re
from collections import Counter

try:
    from .ump_inspect import media_header, ump_uint
except ImportError:
    from ump_inspect import media_header, ump_uint

# Protocol control, not audio/video bytes. Unknown types are rejected.
CONTROL_PARTS = {10, 11, *range(30, 39), *range(42, 73)}
MEDIA_PARTS = {12, 21, 22}


class UmpGate:
    def __init__(self, target_id):
        if not re.fullmatch(r'[A-Za-z0-9_-]{11}', target_id):
            raise ValueError('Invalid video identifier')
        self.target_id = target_id
        self.prefix = bytearray()
        self.payload = bytearray()
        self.kind = None
        self.remaining = 0
        self.mode = None
        self.headers = {}
        self.events = []
        self.decisions = Counter()
        self.parts = Counter()
        self.bytes_in = self.bytes_out = self.bytes_dropped = 0
        self.media_allowed = self.media_blocked = 0
        self.error = None
        self.finished = False
        self.encrypted_chain_broken = False

    def _fail(self, reason):
        if not self.error:
            self.error = reason
            self.events.append({'decision': 'blocked_unknown', 'reason': reason})
        self.bytes_dropped += len(self.prefix) + len(self.payload)
        self.prefix.clear()
        self.payload.clear()
        self.headers.clear()

    def _emit(self, data, output):
        output.extend(data)
        self.bytes_out += len(data)

    def _start(self, output):
        if self.kind == 20:
            if self.remaining > 16384:
                self._fail('Media header too large; remainder of response blocked')
            self.mode = 'header'
        elif self.kind in MEDIA_PARTS:
            self.mode = 'id'
        elif self.kind in CONTROL_PARTS:
            self.mode = 'pass'
            self._emit(self.prefix, output)
            self.prefix.clear()
        else:
            self.mode = 'drop'
            self.bytes_dropped += len(self.prefix)
            self.prefix.clear()
            self.events.append({'partType': self.kind, 'decision': 'blocked_unknown',
                                'reason': 'Unrecognized UMP block type'})

    def _finish_part(self, output):
        if self.mode == 'header':
            try:
                header = media_header(self.payload)
            except (ValueError, UnicodeError):
                self._fail('Unreadable media header; remainder of response blocked')
                return
            header_id, video_id = header.get('headerId'), header.get('videoId')
            allowed = header_id is not None and video_id == self.target_id
            decision = 'allowed_target' if allowed else 'blocked_other' if video_id else 'blocked_unknown'
            if header_id is not None:
                if header_id not in self.headers and len(self.headers) >= 4096:
                    self._fail('Too many headers; remainder of response blocked')
                    return
                self.headers[header_id] = (allowed, video_id)
            else:
                # Do not reuse an earlier mapping after an ambiguous header.
                self.headers.clear()
                decision = 'blocked_unknown'
            self.decisions[decision] += 1
            self.events.append({'decision': decision, 'ump_header': header,
                                'reason': 'Selected video' if allowed else
                                'Other video; advertising status unconfirmed' if video_id else 'Missing identifier'})
            raw = self.prefix + self.payload
            if allowed:
                self._emit(raw, output)
            else:
                self.bytes_dropped += len(raw)
        elif self.mode == 'id':
            # Empty media block or truncated identifier: nothing has been forwarded.
            self.bytes_dropped += len(self.prefix) + len(self.payload)
            self.events.append({'decision': 'blocked_unknown', 'partType': self.kind,
                                'reason': 'Missing or truncated block identifier'})
        self.prefix.clear()
        self.payload.clear()
        self.kind = self.mode = None

    def feed(self, chunk):
        if self.finished:
            raise ValueError('Response already finished')
        self.bytes_in += len(chunk)
        if not chunk:
            self.finished = True
            if self.prefix or self.kind is not None:
                self._fail('Truncated UMP response')
            return b''
        if self.error:
            self.bytes_dropped += len(chunk)
            return b''
        output = bytearray()
        view = memoryview(chunk)
        offset = 0
        while offset < len(view):
            if self.kind is None:
                self.prefix.append(view[offset])
                offset += 1
                first = ump_uint(self.prefix)
                second = ump_uint(self.prefix, first[1]) if first else None
                if not second:
                    continue
                self.kind, self.remaining = first[0], second[0]
                self.parts[str(self.kind)] += 1
                self._start(output)
            if self.error:
                self.bytes_dropped += len(view) - offset
                break
            if self.mode == 'id' and self.remaining and offset == len(view):
                break
            if self.mode == 'id' and self.remaining:
                self.payload.append(view[offset])
                offset += 1
                self.remaining -= 1
                parsed = ump_uint(self.payload)
                if parsed:
                    header_id = parsed[0]
                    allowed, video_id = self.headers.get(header_id, (False, None))
                    if self.kind == 12:
                        if self.encrypted_chain_broken:
                            allowed = False
                        if not allowed:
                            self.encrypted_chain_broken = True
                    self.mode = 'pass' if allowed else 'drop'
                    raw = self.prefix + self.payload
                    if allowed:
                        self._emit(raw, output)
                    else:
                        self.bytes_dropped += len(raw)
                    if header_id not in self.headers:
                        self.events.append({'decision': 'blocked_unknown', 'partType': self.kind,
                                            'headerId': header_id, 'reason': 'Unknown associated header'})
                    elif self.kind == 12 and not allowed and video_id == self.target_id:
                        self.events.append({'decision': 'blocked_unknown', 'partType': self.kind,
                                            'headerId': header_id,
                                            'reason': 'Encryption chain interrupted by a removed block'})
                    self.prefix.clear()
                    self.payload.clear()
            elif self.mode != 'id':
                take = min(self.remaining, len(view) - offset)
                data = view[offset:offset + take]
                if self.mode == 'header':
                    self.payload.extend(data)
                elif self.mode == 'pass':
                    self._emit(data, output)
                    if self.kind in (12, 21):
                        self.media_allowed += take
                else:
                    self.bytes_dropped += take
                    if self.kind in (12, 21):
                        self.media_blocked += take
                offset += take
                self.remaining -= take
            if not self.remaining:
                self._finish_part(output)
            if self.error:
                self.bytes_dropped += len(view) - offset
                break
        return bytes(output)

    def take_events(self):
        events, self.events = self.events, []
        return events

    def summary(self):
        return {'targetVideoId': self.target_id, 'receivedBytes': self.bytes_in,
                'forwardedBytes': self.bytes_out, 'withheldBytes': self.bytes_dropped,
                'allowedMediaBytes': self.media_allowed, 'blockedMediaBytes': self.media_blocked,
                'decisions': dict(self.decisions), 'parts': dict(self.parts), 'parseError': self.error}
