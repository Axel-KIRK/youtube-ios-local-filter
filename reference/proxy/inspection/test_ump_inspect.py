import unittest
from inspection.ump_inspect import UmpInspector, ump_uint


class UmpTests(unittest.TestCase):
    def test_varints_from_protocol_boundaries(self):
        for data, expected in [(b'\x7f',127),(b'\x80\x02',128),(b'\xc0\x00\x02',16384),
                               (b'\xe0\x00\x00\x02',2097152),(b'\xf0\x78\x56\x34\x12',0x12345678)]:
            self.assertEqual(ump_uint(data),(expected,len(data)))
            self.assertIsNone(ump_uint(data[:-1]))

    def test_chunk_boundaries_preserve_video_identity(self):
        header=b'\x08\x01\x12\x0bABCDEFGHIJK\x18\x89\x01\x60\xe8\x07'
        stream=bytes([20,len(header)])+header+b'\x15\x04xxxx\x16\x01\x01'
        for size in range(1,len(stream)+1):
            parser=UmpInspector(); got=[]
            for start in range(0,len(stream),size):got.extend(parser.feed(stream[start:start+size]))
            self.assertEqual(got,[{'headerId':1,'videoId':'ABCDEFGHIJK','itag':137,'durationMs':1000}])
            self.assertEqual(parser.total_bytes,len(stream))
            self.assertFalse(parser.payload)

    def test_large_video_body_is_never_buffered(self):
        parser=UmpInspector()
        parser.feed(b'\x15\xf0\x00\x00\x10\x00')  # MEDIA, 1 MiB
        for _ in range(16):
            parser.feed(b'x'*65536)
            self.assertLessEqual(len(parser.payload)+len(parser.prefix),10)
        self.assertIsNone(parser.kind)
        self.assertEqual(parser.headers,[])

    def test_invalid_header_stops_analysis_without_throwing(self):
        parser=UmpInspector()
        self.assertEqual(parser.feed(b'\x14\x02\xff\xff'),[])
        self.assertIsNotNone(parser.error)
        self.assertEqual(parser.feed(b'more media'),[])


if __name__=='__main__':unittest.main()
