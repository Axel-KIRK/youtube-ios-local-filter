"""Read only UMP headers; skip media bytes without retaining them.

Schema: github.com/LuanRT/googlevideo, protos/video_streaming/media_header.proto.
UMP varints use a length prefix and differ from Protobuf varints."""
import re
from collections import Counter
try:
    from .api_inspect import wire_fields
except ImportError:
    from api_inspect import wire_fields


def ump_uint(data, offset=0):
    if offset >= len(data):
        return None
    first = data[offset]
    length = 1 if first < 128 else 2 if first < 192 else 3 if first < 224 else 4 if first < 240 else 5
    if len(data) - offset < length:
        return None
    if length == 1:
        return first, offset + 1
    tail = int.from_bytes(data[offset + 1:offset + length], 'little')
    if length == 5:
        return tail, offset + 5
    bits = 8 - length
    return (first & ((1 << bits) - 1)) | (tail << bits), offset + length


def media_header(data):
    numeric = {1:'headerId', 3:'itag', 6:'segmentByteStart', 8:'initialization',
               9:'segmentNumber', 10:'bitrateBps', 11:'startMs', 12:'durationMs',
               14:'segmentBytes'}
    result = {}
    identifiers = set()
    for number, kind, value in wire_fields(data):
        if number in (1, 2):
            if number in identifiers or kind != (0 if number == 1 else 2):
                raise ValueError('Ambiguous media identifier')
            identifiers.add(number)
        if number in numeric and kind == 0:
            result[numeric[number]] = value
        elif number == 2 and kind == 2:
            video_id = value.decode('ascii', 'strict')
            if re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
                result['videoId'] = video_id
            else:
                raise ValueError('Invalid video identifier')
    return result


class UmpInspector:
    def __init__(self):
        self.prefix = bytearray()
        self.payload = bytearray()
        self.remaining = 0
        self.kind = None
        self.keep = False
        self.total_bytes = 0
        self.parts = Counter()
        self.headers = []
        self.error = None

    def feed(self, chunk):
        self.total_bytes += len(chunk)
        if self.error:
            return []
        emitted = []
        view = memoryview(chunk)
        offset = 0
        try:
            while offset < len(view):
                if self.kind is None:
                    self.prefix.append(view[offset]); offset += 1
                    first = ump_uint(self.prefix)
                    second = ump_uint(self.prefix, first[1]) if first else None
                    if not second:
                        continue
                    self.kind, self.remaining = first[0], second[0]
                    self.parts[str(self.kind)] += 1
                    self.keep = self.kind == 20 and self.remaining <= 16384 and len(self.headers) < 64
                    self.prefix.clear()
                take = min(self.remaining, len(view) - offset)
                if self.keep:
                    self.payload.extend(view[offset:offset + take])
                offset += take
                self.remaining -= take
                if self.remaining == 0:
                    if self.keep:
                        item = media_header(self.payload)
                        if item:
                            self.headers.append(item)
                            emitted.append(item)
                    self.payload.clear()
                    self.kind = None
        except (ValueError, UnicodeError):
            self.error = 'Unrecognized UMP header; stream unchanged'
            self.payload.clear()
            self.prefix.clear()
        return emitted

    def summary(self):
        return {'parts':dict(self.parts), 'mediaHeaders':self.headers,
                'bytesObserved':self.total_bytes, 'parseError':self.error}
