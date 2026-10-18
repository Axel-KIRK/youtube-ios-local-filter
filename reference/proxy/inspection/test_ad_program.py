import gzip
import hashlib
import hmac
import unittest
from pathlib import Path
from inspection import ad_program as a
from inspection.test_navigation import f
from inspection.test_ump_filter import header, media
from inspection.ump_inspect import ump_uint

KEY = bytes(range(32))
IV = bytes(range(16))
PLAYER = f(2, b'') + f(11, f(1, b'thbQYUvfLFQ')) + f(68, b'ad-slot') + f(4, b'stream-urls') + f(777, b'unknown')
CLEAN = f(2, b'') + f(11, f(1, b'thbQYUvfLFQ')) + f(4, b'stream-urls') + f(777, b'unknown')


def encrypted_pair(kind=25, compressed=True, bad=False):
    envelope = f(1, 1) + f(2, 200) + f(4, f(2, PLAYER) if kind == 25 else PLAYER)
    cipher = a.crypt(KEY, IV, gzip.compress(envelope) if compressed else envelope)
    tag = hmac.new(KEY[16:], cipher + IV, hashlib.sha256).digest()
    if kind == 25:
        return a.part(10, f(1, 25) + f(4, b'')) + a.part(11, f(1, cipher) + f(2, b'x' * 32 if bad else tag) + f(3, IV) + f(4, int(compressed)))
    params = f(4, b'x' * 32 if bad else tag) + f(5, IV) + f(6, int(compressed))
    return a.part(10, f(1, kind) + f(4, params)) + a.part(11, cipher)


def parts(data):
    result = []
    pos = 0
    while pos < len(data):
        kind, pos = ump_uint(data, pos)
        size, pos = ump_uint(data, pos)
        result.append((kind, data[pos:pos + size])); pos += size
    return result


class AdProgramTests(unittest.TestCase):
    def test_only_ads_removed_and_other_wire_bytes_preserved(self):
        result, reports = a.rewrite_api(PLAYER, '/youtubei/v1/player', True)
        self.assertEqual(result, CLEAN)
        self.assertEqual(reports[0]['adFields'], {'adSlots': 1})
        raw = f(1, f(2, PLAYER) + f(3, b'watch next untouched'))
        result, _ = a.rewrite_api(raw, '/youtubei/v1/get_watch', True)
        self.assertEqual(result, f(1, f(2, CLEAN) + f(3, b'watch next untouched')))

    def test_encrypted_gzip_response_authenticated_modified_and_media_untouched(self):
        for kind in (0, 25):
            raw = encrypted_pair(kind)
            media_bytes = header(1) + media(1, b'unchanged video')
            for step in (1, 7, len(raw)):
                stream = a.AdProgramStream(KEY, True)
                source = raw + media_bytes
                result = b''.join(stream.feed(source[i:i + step]) for i in range(0, len(source), step)) + stream.feed(b'')
                self.assertTrue(result.endswith(media_bytes))
                hp, dp = parts(result)[:2]
                params = a.one(a.wire_fields(hp[1]), 4, 2) if kind == 0 else dp[1]
                tag, iv = (a.one(a.wire_fields(params), n, 2) for n in ((4, 5) if kind == 0 else (2, 3)))
                cipher = dp[1] if kind == 0 else a.one(a.wire_fields(dp[1]), 1, 2)
                self.assertNotEqual(iv, IV)
                self.assertEqual(tag, hmac.new(KEY[16:], cipher + iv, hashlib.sha256).digest())
                envelope = gzip.decompress(a.crypt(KEY, iv, cipher))
                self.assertEqual(a.one(a.wire_fields(envelope), 4, 2), f(2, CLEAN) if kind == 25 else CLEAN)
                self.assertTrue(stream.modified)

    def test_observe_bad_hmac_missing_key_truncation_and_unknown_passthrough(self):
        for key, enabled, raw in [(KEY, False, encrypted_pair()), (None, True, encrypted_pair()),
                                  (KEY, True, encrypted_pair(bad=True)),
                                  (KEY, True, encrypted_pair()[:-8]),
                                  (KEY, True, a.part(10, b'unknown') + a.part(11, b'unknown'))]:
            stream = a.AdProgramStream(key, enabled)
            self.assertEqual(stream.feed(raw) + stream.feed(b''), raw)
            self.assertFalse(stream.modified)

    def test_nonplayer_or_malformed_body_is_unchanged(self):
        for raw in (b'\xff', f(68, b'opaque'), f(11, f(1, b'invalid-id'))):
            self.assertEqual(a.rewrite_api(raw, '/youtubei/v1/player', True)[0], raw)

    def test_clear_onesie_response_preserves_envelope_and_media(self):
        raw = a.part(10, f(1, 0) + f(4, b'')) + a.part(11, f(1, 1) + f(2, 200) + f(4, PLAYER))
        stream = a.AdProgramStream(None, True)
        result = stream.feed(raw) + stream.feed(b'')
        self.assertEqual(parts(result)[1][1], f(1, 1) + f(2, 200) + f(4, CLEAN))
        self.assertTrue(stream.modified)

    def test_large_control_and_unpaired_headers_are_passed_unchanged(self):
        from unittest.mock import patch
        raw = a.part(10, f(1, 25)) + a.part(11, b'x' * 100) + a.part(10, b'hi') + a.part(20, b'media')
        with patch.object(a, 'LIMIT', 50):
            stream = a.AdProgramStream(KEY, True)
            self.assertEqual(b''.join(stream.feed(bytes([v])) for v in raw) + stream.feed(b''), raw)

    def test_ump_sizes_roundtrip(self):
        for n in (0, 127, 128, 16383, 16384, 2097151, 2097152, 2**28 - 1, 2**28, 2**32 - 1):
            self.assertEqual(ump_uint(a.uint(n)), (n, len(a.uint(n))))


if __name__ == '__main__':
    unittest.main()
