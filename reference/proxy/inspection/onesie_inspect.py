"""Lecture locale de l'enveloppe de démarrage ; clés uniquement en mémoire.

AES-CTR + HMAC-SHA256 selon le protocole public Onesie. Ni requête déchiffrée,
ni clés, ni en-têtes d'authentification ne sont journalisés ou transmis ailleurs.
"""
import base64
import hashlib
import hmac
import time
import zlib
from urllib.parse import urlsplit

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

try:
    from .navigation_inspect import one, inspect_navigation
    from .api_inspect import wire_fields
except ImportError:
    from navigation_inspect import one, inspect_navigation
    from api_inspect import wire_fields


def child(data, number):
    return one(wire_fields(data), number, 2) if data else None


class KeyVault:
    def __init__(self):
        self.keys = {}

    def ready(self, client):
        return any(owner == client and expires > time.time() for (owner, _), (_, expires) in self.keys.items())

    def capture(self, body, client):
        try:
            group = child(child(body, 1), 16)
            if not group:
                return False
            fields = wire_fields(group)
            hot = one(fields, 7, 2)
            if hot is None:
                encoded = one(fields, 3, 2)
                if not encoded:
                    return False
                hot = base64.b64decode(encoded + b'=' * (-len(encoded) % 4), altchars=b'-_', validate=True)
            config = child(child(hot, 138536474), 146311580)
            fields = wire_fields(config) if config else []
            key, wrapped = one(fields, 1, 2), one(fields, 2, 2)
            expires_in = one(fields, 3, 0)
            if not key or len(key) != 32 or not wrapped or not 16 <= len(wrapped) <= 1024:
                return False
            identity = (client, hashlib.sha256(wrapped).digest())
            self.keys[identity] = (key, time.time() + min(expires_in or 1800, 3600))
            self.keys = {k: v for k, v in list(self.keys.items())[-32:] if v[1] > time.time()}
            return True
        except (ValueError, TypeError, OverflowError):
            return False

    def inspect(self, body, client):
        if not body or len(body) > 1024 * 1024:
            return None
        try:
            root = wire_fields(body)
            encrypted = one(root, 3, 2)
            if encrypted is None:
                return None
            target = one(root, 13, 0)
            fields = wire_fields(encrypted)
            plain = one(fields, 16, 2)
            if plain is None:
                cipher, wrapped, iv, tag = (one(fields, n, 2) for n in (2, 5, 6, 7))
                if not all((cipher, wrapped, iv, tag)) or len(iv) != 16 or len(tag) != 32:
                    return {'eligible': False, 'onesieStatus': 'incomplete', 'requestTarget': target}
                entry = self.keys.get((client, hashlib.sha256(wrapped).digest()))
                if not entry or entry[1] <= time.time():
                    return {'eligible': False, 'onesieStatus': 'key_unavailable', 'requestTarget': target}
                key = entry[0]
                signature = hmac.new(key[16:], cipher + iv, hashlib.sha256).digest()
                if not hmac.compare_digest(signature, tag):
                    return {'eligible': False, 'onesieStatus': 'hmac_mismatch', 'requestTarget': target}
                decryptor = Cipher(algorithms.AES(key[:16]), modes.CTR(iv)).decryptor()
                plain = decryptor.update(cipher) + decryptor.finalize()
                if one(fields, 8, 0):
                    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
                    plain = decoder.decompress(plain, 1024 * 1024 + 1)
                    if len(plain) > 1024 * 1024 or not decoder.eof:
                        return {'eligible': False, 'onesieStatus': 'compression_limit'}
            envelope = wire_fields(plain)
            url, post_body = one(envelope, 1, 2), one(envelope, 3, 2)
            url = urlsplit((url or b'').decode('ascii'))
            if url.hostname not in (None, 'youtubei.googleapis.com', 'youtubei-att.googleapis.com', 'www.youtube.com'):
                return {'eligible': False, 'onesieStatus': 'unexpected_destination'}
            navigation = inspect_navigation(post_body or b'', url.path)
            return {**(navigation or {'eligible': False}), 'onesieStatus': 'decoded',
                    'requestTarget': target, 'innerPath': url.path}
        except (ValueError, TypeError, UnicodeError, OverflowError, zlib.error):
            return {'eligible': False, 'onesieStatus': 'unrecognized'}


# Le module persiste lors du rechargement de l'addon ; aucune clé écrite sur disque.
vault = KeyVault()
