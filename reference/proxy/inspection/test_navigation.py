import hashlib
import hmac
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from inspection.navigation_inspect import inspect_navigation
from inspection.onesie_inspect import KeyVault
from inspection.auto_video_filter import AutoSelector

VID = b'thbQYUvfLFQ'


def varint(n):
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128); n >>= 7
    return bytes(out) + bytes([n])


def f(n, value):
    return varint(n << 3) + varint(value) if isinstance(value, int) else varint((n << 3) | 2) + varint(len(value)) + value


class NavigationTests(unittest.TestCase):
    def test_only_watch_navigation_selects_and_ad_preview_queue_do_not(self):
        watch = f(2, VID) + f(14, 1)
        for path, body in [('/youtubei/v1/next', watch), ('/youtubei/v1/get_watch', f(3, watch))]:
            self.assertTrue(inspect_navigation(body, path)['eligible'])
        for extra in (f(9, 1), f(42, 1), f(8, b'continuation')):
            self.assertFalse(inspect_navigation(watch + extra, '/youtubei/v1/next')['eligible'])
        self.assertFalse(inspect_navigation(f(2, VID) + f(14, 7), '/youtubei/v1/next')['eligible'])
        self.assertFalse(inspect_navigation(f(2, VID), '/youtubei/v1/player')['eligible'])

    def test_malformed_ambiguous_or_missing_id_cannot_select(self):
        for body in (f(2, VID) * 2, f(2, b'bad'), b'\xff\xff', f(1, b'')):
            self.assertFalse(inspect_navigation(body, '/youtubei/v1/next')['eligible'])

    def test_decodes_authenticated_onesie_before_media_without_logging_secrets(self):
        key = bytes(range(32)); wrapped = b'wrapped-test-key' * 4; iv = bytes(range(16))
        config = f(1, f(16, f(7, f(138536474, f(146311580, f(1, key) + f(2, wrapped))))))
        vault = KeyVault()
        self.assertTrue(vault.capture(config, 'phone'))
        body = f(1, b'https://youtubei.googleapis.com/youtubei/v1/get_watch?key=PRIVATE') + f(3, f(3, f(2, VID) + f(14, 1)))
        crypt = Cipher(algorithms.AES(key[:16]), modes.CTR(iv)).encryptor()
        cipher = crypt.update(body) + crypt.finalize()
        tag = hmac.new(key[16:], cipher + iv, hashlib.sha256).digest()
        request = f(3, f(2, cipher) + f(5, wrapped) + f(6, iv) + f(7, tag)) + f(13, 3)
        result = vault.inspect(request, 'phone')
        self.assertTrue(result['eligible'])
        self.assertEqual(result['videoId'], VID.decode())
        self.assertNotIn('PRIVATE', str(result))
        self.assertEqual(vault.inspect(request, 'other-phone')['onesieStatus'], 'key_unavailable')
        altered = f(3, f(2, cipher) + f(5, wrapped) + f(6, iv) + f(7, b'X' * 32))
        self.assertEqual(vault.inspect(altered, 'phone')['onesieStatus'], 'hmac_mismatch')

    def test_auto_target_changes_and_expires_without_retry_extension(self):
        clock = [1000.0]
        with tempfile.TemporaryDirectory() as d:
            selector = AutoSelector(Path(d) / 'state.json', clock=lambda: clock[0])
            candidate = {'eligible': True, 'videoId': VID.decode(), 'source': 'get_watch'}
            self.assertIsNotNone(selector.consider('phone', candidate, 45, 'first'))
            clock[0] += 20
            self.assertIsNone(selector.consider('phone', candidate, 45, 'retry'))
            self.assertEqual(selector.active('phone')['expiresAtEpoch'], 1045)
            self.assertIsNone(selector.active('other-phone'))
            selector.consider('phone', {**candidate, 'videoId': '4glFOauBUhQ'}, 45, 'second')
            self.assertEqual(selector.active('phone')['videoId'], '4glFOauBUhQ')
            clock[0] += 46
            self.assertIsNone(selector.active('phone'))


if __name__ == '__main__':
    unittest.main()
