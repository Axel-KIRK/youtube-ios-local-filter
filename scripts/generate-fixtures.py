#!/usr/bin/env python3
"""Generate synthetic cross-language fixtures; never reads runtime captures."""
import base64
import gzip
import hashlib
import hmac
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'reference/proxy'))
from inspection import ad_program as a

KEY = bytes(range(32))  # Public synthetic test material, not a device/session key.
IV = bytes(range(16))
f = a.field
n = lambda field, value: a.vint(field << 3) + a.vint(value)
clean = f(2, b'') + f(11, f(1, b'demoVideo01')) + f(4, b'synthetic media info') + f(777, b'unknown')
player = clean + f(7, b'first') + f(7, b'second') + f(45, b'placement') + f(68, b'slot')
media = a.part(20, n(1, 1) + f(2, b'demoVideo01')) + a.part(12, b'opaque synthetic media' * 40)
fixtures = []
for kind in (0, 25):
    for compressed in (False, True):
        plain = n(1, 1) + n(2, 200) + f(4, f(2, player) if kind == 25 else player) + f(123, b'keep')
        expected = n(1, 1) + n(2, 200) + f(4, f(2, clean) if kind == 25 else clean) + f(123, b'keep')
        cipher = a.crypt(KEY, IV, gzip.compress(plain, mtime=0) if compressed else plain)
        tag = hmac.new(KEY[16:], cipher + IV, hashlib.sha256).digest()
        if kind == 25:
            header = n(1, 25) + f(4, b'')
            body = f(1, cipher) + f(2, tag) + f(3, IV) + n(4, int(compressed)) + f(99, b'preserve')
        else:
            header = n(1, 0) + f(4, f(4, tag) + f(5, IV) + n(6, int(compressed)))
            body = cipher
        stream = a.part(10, header) + a.part(11, body) + media
        entry = {'name': f'type-{kind}-gzip-{compressed}', 'kind': kind, 'compressed': compressed,
                 'key': KEY, 'iv': IV, 'input': stream, 'originalPlain': plain,
                 'expectedPlain': expected, 'media': media}
        fixtures.append({k: base64.b64encode(v).decode() if isinstance(v, bytes) else v for k, v in entry.items()})
path = ROOT / 'Tests/LocalFilterCoreTests/Fixtures/onesie.json'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(fixtures, indent=2) + '\n')
print(path.relative_to(ROOT))
