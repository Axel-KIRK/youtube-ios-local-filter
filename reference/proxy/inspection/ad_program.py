"""Retire uniquement les champs de programmation publicitaire du PlayerResponse.

Les médias restent inchangés. Les champs inconnus sont conservés octet pour octet.
Onesie est vérifié, déchiffré puis rechiffré localement ; aucune clé n'est persistée.
Enveloppe inconnue, tronquée ou trop grande : transmission originale.
"""
import gzip
import hashlib
import hmac
import os
import time
import zlib
from collections import Counter
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
try:
    from .api_inspect import wire_fields
    from .navigation_inspect import one, video_id
    from .ump_inspect import ump_uint
except ImportError:
    from api_inspect import wire_fields
    from navigation_inspect import one, video_id
    from ump_inspect import ump_uint

LIMIT = 4 * 1024 * 1024
AD_FIELDS = {7: 'playerAds', 45: 'adPlacements', 68: 'adSlots'}


def vint(n):
    result = bytearray()
    while n > 127:
        result.append((n & 127) | 128)
        n >>= 7
    return bytes(result) + bytes([n])


def field(n, value):
    return vint(n << 3 | 2) + vint(len(value)) + value


def spans(data):
    """Wire fields with original serialized bytes, including noncanonical varints."""
    fields = wire_fields(data)
    offset = 0
    for n, k, value in fields:
        start = offset
        while data[offset] & 128:
            offset += 1
        offset += 1
        if k in (0, 2):
            while data[offset] & 128:
                offset += 1
            offset += 1
        if k != 0:
            offset += len(value)
        yield n, k, value, data[start:offset]


def transform(data, number, callback):
    result = []
    for n, k, value, raw in spans(data):
        replacement = callback(value) if n == number and k == 2 else value
        result.append(field(n, replacement) if replacement != value else raw)
    return b''.join(result)


def rewrite_player(data, reports, enabled):
    fields = wire_fields(data)
    details = one(fields, 11, 2)
    vid = video_id(one(wire_fields(details), 1, 2)) if details else None
    if not vid or not any(n in (2, 4) and k == 2 for n, k, _ in fields):
        return data
    counts = Counter(AD_FIELDS[n] for n, k, _ in fields if n in AD_FIELDS and k == 2)
    reports.append({'videoId': vid, 'adFields': dict(counts), 'removed': bool(enabled and counts)})
    if not enabled or not counts:
        return data
    return b''.join(raw for n, k, _, raw in spans(data) if not (n in AD_FIELDS and k == 2))


def rewrite_watch(data, reports, enabled):
    return transform(data, 2, lambda player: rewrite_player(player, reports, enabled))


def rewrite_api(data, path, enabled):
    reports = []
    try:
        if len(data) > LIMIT:
            return data, reports
        if path.endswith('/player'):
            result = rewrite_player(data, reports, enabled)
        elif path.endswith('/get_watch'):
            # HTTP get_watch is a repeated field-1 stream of GetWatchResponse.
            result = transform(data, 1, lambda watch: rewrite_watch(watch, reports, enabled))
        else:
            result = data
        return result, reports
    except (ValueError, UnicodeError, TypeError, IndexError):
        return data, [{'status': 'unrecognized', 'removed': False}]


def request_key(body, client, vault):
    try:
        envelope = one(wire_fields(body), 3, 2)
        wrapped = one(wire_fields(envelope), 5, 2)
        entry = vault.keys.get((client, hashlib.sha256(wrapped).digest()))
        return entry[0] if entry and entry[1] > time.time() else None
    except (ValueError, TypeError):
        return None


def crypt(key, iv, data):
    operation = Cipher(algorithms.AES(key[:16]), modes.CTR(iv)).encryptor()
    return operation.update(data) + operation.finalize()


def uint(n):
    for length, bits in ((1, 7), (2, 14), (3, 21), (4, 28)):
        if n < 1 << bits:
            if length == 1:
                return bytes([n])
            low = 8 - length
            return bytes([((0xff << (9 - length)) & 255) | (n & ((1 << low) - 1))]) + (n >> low).to_bytes(length - 1, 'little')
    return b'\xf0' + n.to_bytes(4, 'little')


def part(kind, payload):
    return uint(kind) + uint(len(payload)) + payload


class AdProgramStream:
    def __init__(self, key=None, enabled=False):
        self.key, self.enabled = key, enabled
        self.prefix = bytearray()
        self.payload = bytearray()
        self.kind = None
        self.remaining = 0
        self.keep = False
        self.pending = None
        self.events = []
        self.modified = False
        self.data_started = None

    def rewrite_response_part(self, data):
        """Type 25 carries its own ciphertext/IV/HMAC in EncryptedInnertubeResponsePart."""
        fields = wire_fields(data)
        cipher, tag, iv = (one(fields, n, 2) for n in (1, 2, 3))
        compression = one(fields, 4, 0) or 0
        if not self.key or not cipher or not tag or not iv or len(tag) != 32 or len(iv) != 16:
            raise ValueError('incomplete response part')
        if not hmac.compare_digest(tag, hmac.new(self.key[16:], cipher + iv, hashlib.sha256).digest()):
            raise ValueError('hmac')
        plain = crypt(self.key, iv, cipher)
        if compression == 1:
            decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
            plain = decoder.decompress(plain, LIMIT + 1)
            if len(plain) > LIMIT or not decoder.eof or decoder.unused_data:
                raise ValueError('compression')
        elif compression != 0:
            raise ValueError('compression')
        fields = wire_fields(plain)
        if one(fields, 1, 0) not in (None, 1) or one(fields, 2, 0) not in (None, 200):
            raise ValueError('response status')
        reports = []
        rewritten = transform(plain, 4, lambda watch: rewrite_watch(watch, reports, self.enabled))
        self.events.append({'status': 'decoded', 'headerType': 25, 'players': reports,
                            'encryptedEnvelope': True, 'modified': rewritten != plain})
        if rewritten == plain:
            return data
        if compression == 1:
            rewritten = gzip.compress(rewritten, mtime=0)
        new_iv = os.urandom(16)
        cipher = crypt(self.key, new_iv, rewritten)
        tag = hmac.new(self.key[16:], cipher + new_iv, hashlib.sha256).digest()
        result = transform(transform(transform(data, 1, lambda _: cipher), 2, lambda _: tag), 3, lambda _: new_iv)
        self.modified = True
        return result

    def rewrite_pair(self, header, data):
        try:
            fields = wire_fields(header)
            kind = one(fields, 1, 0) or 0
            if kind == 25:
                return header, self.rewrite_response_part(data)
            params = one(fields, 4, 2)
            if kind not in (0, 25) or params is None:
                return header, data
            fields = wire_fields(params)
            tag, iv = one(fields, 4, 2), one(fields, 5, 2)
            compression = one(fields, 6, 0) or 0
            clear = not tag and not iv
            if not clear and (not self.key or not tag or not iv or len(iv) != 16 or len(tag) != 32):
                self.events.append({'status': 'key_or_crypto_unavailable', 'headerType': kind,
                                    'keyAvailable': bool(self.key), 'ivBytes': len(iv or b''),
                                    'tagBytes': len(tag or b''), 'compression': compression})
                return header, data
            if not clear and not hmac.compare_digest(tag, hmac.new(self.key[16:], data + iv, hashlib.sha256).digest()):
                raise ValueError('hmac')
            plain = data if clear else crypt(self.key, iv, data)
            if compression == 1:
                decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
                plain = decoder.decompress(plain, LIMIT + 1)
                if len(plain) > LIMIT or not decoder.eof or decoder.unused_data:
                    raise ValueError('compression')
            elif compression != 0:
                raise ValueError('compression')
            fields = wire_fields(plain)
            # Require successful Onesie HTTP envelope, never guess at opaque bytes.
            if one(fields, 1, 0) != 1 or one(fields, 2, 0) != 200:
                raise ValueError('response status')
            reports = []
            def body(value):
                return (rewrite_player(value, reports, self.enabled) if kind == 0
                        else rewrite_watch(value, reports, self.enabled))
            rewritten = transform(plain, 4, body)
            self.events.append({'status': 'decoded', 'headerType': kind, 'players': reports,
                                'encryptedEnvelope': not clear, 'modified': rewritten != plain})
            if rewritten == plain:
                return header, data
            if compression == 1:
                rewritten = gzip.compress(rewritten, mtime=0)
            if clear:
                self.modified = True
                return header, rewritten
            new_iv = os.urandom(16)
            cipher = crypt(self.key, new_iv, rewritten)
            new_tag = hmac.new(self.key[16:], cipher + new_iv, hashlib.sha256).digest()
            params = transform(transform(params, 4, lambda _: new_tag), 5, lambda _: new_iv)
            header = transform(header, 4, lambda _: params)
            self.modified = True
            return header, cipher
        except (ValueError, TypeError, UnicodeError, IndexError, zlib.error):
            self.events.append({'status': 'unrecognized_or_unauthenticated', 'modified': False})
            return header, data

    def feed(self, chunk):
        output = bytearray()
        if not chunk:
            if self.pending:
                output.extend(self.pending[0])
            output.extend(self.prefix)
            output.extend(self.payload)
            self.pending = None
            self.prefix.clear()
            self.payload.clear()
            return bytes(output)
        offset = 0
        while offset < len(chunk):
            if self.kind is None:
                self.prefix.append(chunk[offset]); offset += 1
                first = ump_uint(self.prefix)
                second = ump_uint(self.prefix, first[1]) if first else None
                if not second:
                    continue
                self.kind, self.remaining = first[0], second[0]
                self.keep = self.kind in (10, 11) and self.remaining <= LIMIT
                self.data_started = time.perf_counter() if self.kind == 11 and self.pending and self.keep else None
                if self.pending and (self.kind != 11 or not self.keep):
                    output.extend(self.pending[0]); self.pending = None
                if not self.keep:
                    output.extend(self.prefix); self.prefix.clear()
            take = min(self.remaining, len(chunk) - offset)
            piece = chunk[offset:offset + take]
            if self.keep:
                self.payload.extend(piece)
            else:
                output.extend(piece)
            offset += take
            self.remaining -= take
            if self.remaining == 0:
                if self.keep:
                    payload = bytes(self.payload)
                    raw = bytes(self.prefix) + payload
                    if self.kind == 10:
                        self.pending = (raw, payload)
                    elif self.pending:
                        old_raw, old_header = self.pending
                        started = time.perf_counter()
                        event_offset = len(self.events)
                        header, data = self.rewrite_pair(old_header, payload)
                        processing_ms = round((time.perf_counter() - started) * 1000, 3)
                        buffering_ms = round((started - (self.data_started or started)) * 1000, 3)
                        for event in self.events[event_offset:]:
                            event.update(processingMs=processing_ms, bufferingMs=buffering_ms)
                        output.extend(old_raw + raw if header == old_header and data == payload
                                      else part(10, header) + part(11, data))
                        self.pending = None
                    else:
                        output.extend(raw)
                self.kind = None
                self.prefix.clear()
                self.payload.clear()
        return bytes(output)
