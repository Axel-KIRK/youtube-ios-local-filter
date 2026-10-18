import random
import unittest

from inspection.ump_filter import UmpGate

TARGET = 'hw2iFtnTygA'
OTHER = 'abcdefghijk'


def u(n):
    for length, maximum in ((1, 128), (2, 16384), (3, 2097152), (4, 268435456)):
        if n < maximum:
            if length == 1:
                return bytes([n])
            bits = 8 - length
            return bytes([(256 - (1 << (9 - length))) | (n & ((1 << bits) - 1))]) + (n >> bits).to_bytes(length - 1, 'little')
    return b'\xf0' + n.to_bytes(4, 'little')


def pb(n):
    output = bytearray()
    while n >= 128:
        output.append((n & 127) | 128)
        n >>= 7
    return bytes(output) + bytes([n])


def part(kind, data):
    return u(kind) + u(len(data)) + data


def header(number, video_id=TARGET):
    return part(20, b'\x08' + pb(number) + (b'\x12\x0b' + video_id.encode() if video_id else b''))


def media(number, data, kind=21):
    return part(kind, u(number) + data)


def run(data, cuts):
    gate = UmpGate(TARGET)
    output = []
    start = 0
    for end in cuts + [len(data)]:
        if end > start:
            output.append(gate.feed(data[start:end]))
            gate.take_events()
        start = end
    output.append(gate.feed(b''))
    return b''.join(output), gate


class GateTests(unittest.TestCase):
    def test_target_audio_video_and_controls_byte_exact_at_every_cut(self):
        stream = part(35, b'control') + header(1) + media(1, b'audio') + header(4096) + media(4096, b'video', 12) + media(4096, b'', 22)
        for cut in range(len(stream) + 1):
            result, gate = run(stream, [cut])
            self.assertEqual(result, stream)
            self.assertEqual(gate.bytes_dropped, 0)
            self.assertIsNone(gate.error)

    def test_foreign_media_never_forwarded_with_shared_chunks_and_id_reuse(self):
        allowed = header(1) + media(1, b'target')
        foreign = header(2, OTHER) + media(2, b'ad-secret') + media(2, b'encrypted-secret', 12) + media(2, b'', 22)
        reuse = header(1, OTHER) + media(1, b'reused-secret')
        tail = header(3) + media(3, b'target-again')
        stream = allowed + foreign + reuse + tail
        randomizer = random.Random(40)
        cuts = [[i] for i in range(len(stream) + 1)] + [list(range(1, len(stream)))]
        cuts += [sorted(randomizer.sample(range(1, len(stream)), 20)) for _ in range(40)]
        for boundaries in cuts:
            result, gate = run(stream, boundaries)
            self.assertEqual(result, allowed + tail)
            self.assertEqual(gate.bytes_in, gate.bytes_out + gate.bytes_dropped)
            self.assertIsNone(gate.error)

    def test_unknown_missing_and_truncated_ids_are_withheld(self):
        stream = media(9, b'unknown') + header(1) + header(1, None) + media(1, b'missing') + part(21, b'\xf0\x00') + part(99, b'unknown-type')
        result, gate = run(stream, list(range(1, len(stream))))
        self.assertEqual(result, header(1))
        self.assertEqual(gate.bytes_in, gate.bytes_out + gate.bytes_dropped)

    def test_mapping_is_not_shared_between_responses(self):
        run(header(1), [])
        result, _ = run(media(1, b'no-current-header'), [])
        self.assertEqual(result, b'')

    def test_encrypted_media_after_a_removed_block_is_withheld(self):
        stream = header(1, OTHER) + media(1, b'cipher-first', 12) + header(2) + media(2, b'cipher-second', 12) + media(2, b'clear-target')
        result, gate = run(stream, list(range(1, len(stream))))
        self.assertEqual(result, header(2) + media(2, b'clear-target'))
        self.assertTrue(gate.encrypted_chain_broken)

    def test_malformed_header_fails_closed_including_later_parts(self):
        stream = part(20, b'\xff\xff') + header(1) + media(1, b'target')
        for size in range(1, len(stream) + 1):
            result, gate = run(stream, list(range(size, len(stream), size)))
            self.assertEqual(result, b'')
            self.assertIsNotNone(gate.error)
            self.assertEqual(gate.bytes_dropped, len(stream))

    def test_large_blocked_media_has_bounded_retained_memory(self):
        gate = UmpGate(TARGET)
        self.assertEqual(gate.feed(header(1, OTHER)), b'')
        self.assertEqual(gate.feed(u(21) + u(1024 * 1024 + 1) + u(1)), b'')
        for _ in range(16):
            self.assertEqual(gate.feed(b'x' * 65536), b'')
            self.assertLessEqual(len(gate.prefix) + len(gate.payload), 10)
        gate.feed(b'')
        self.assertEqual(gate.media_blocked, 1024 * 1024)
        self.assertIsNone(gate.error)

    def test_truncated_header_and_oversize_header_never_escape(self):
        for stream in (header(1)[:-1], u(20) + u(100000) + b'bad'):
            result, gate = run(stream, [])
            self.assertEqual(result, b'')
            self.assertIsNotNone(gate.error)
            self.assertEqual(gate.bytes_dropped, len(stream))

    def test_duplicate_or_wrong_wire_type_video_id_fails_closed(self):
        for payload in (b'\x08\x01\x12\x0b' + TARGET.encode() + b'\x12\x01x',
                        b'\x08\x01\x10\x01', b'\x08\x01\x08\x02\x12\x0b' + TARGET.encode()):
            result, gate = run(part(20, payload) + media(1, b'media'), [])
            self.assertEqual(result, b'')
            self.assertIsNotNone(gate.error)


if __name__ == '__main__':
    unittest.main()
