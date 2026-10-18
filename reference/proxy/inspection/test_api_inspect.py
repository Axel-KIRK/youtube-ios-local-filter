import unittest
from inspection.api_inspect import inspect_body, wire_fields


class InspectionTests(unittest.TestCase):
    def test_player_fields_and_nested_get_watch(self):
        # Player: playabilityStatus=2, playerAds=7, adSlots=68, unknown=99.
        player = b'\x12\x00\x3a\x00\xa2\x04\x00\x98\x06\x01'
        direct = inspect_body(player, '/youtubei/v1/player')
        nested = inspect_body(b'\x0a\x0c\x12\x0a' + player, '/youtubei/v1/get_watch')
        for result in (direct, nested):
            self.assertEqual(result['adPlacements'], 0)
            self.assertEqual(result['playerAds'], 1)
            self.assertEqual(result['adSlots'], 1)
            self.assertEqual(result['playerMessages'], 1)

    def test_onesie_envelope_is_not_assumed_to_be_get_watch(self):
        result = inspect_body(b'\x22\x04\x12\x02\x3a\x00', '/youtubei/v1/get_watch')
        self.assertEqual(result['schema'], 'protobuf-unmapped')
        self.assertEqual(result['adPlacements'], 0)

    def test_malformed_body_is_not_reported_as_a_valid_player(self):
        result = inspect_body(b'\x3a\xff', '/youtubei/v1/player')
        self.assertEqual(result['schema'], 'unparsed')

    def test_unmapped_endpoint_does_not_classify_field_seven_as_an_ad(self):
        result = inspect_body(b'\x3a\x00', '/youtubei/v1/browse')
        self.assertEqual(result['schema'], 'protobuf-unmapped')
        self.assertEqual(result['adPlacements'], 0)

    def test_json_summary_excludes_signatures_and_unrelated_values(self):
        raw = b'{"adPlacements":[{}],"adSlots":[{},{}],"token":"secret","url":"https://rr1.googlevideo.com/videoplayback?sig=SECRET"}'
        result = inspect_body(raw, '/youtubei/v1/player')
        self.assertEqual(result['adSlots'], 2)
        self.assertEqual(result['mediaPaths'], ['https://rr1.googlevideo.com/videoplayback'])
        self.assertNotIn('secret', str(result).lower())

    def test_manifest_path_credentials_are_not_logged(self):
        raw = b'{"url":"https://manifest.googlevideo.com/api/manifest/hls_variant/ip/PRIVATE/signature/SECRET/file.m3u8"}'
        result = inspect_body(raw, '/youtubei/v1/player')
        self.assertEqual(result['mediaPaths'], ['https://manifest.googlevideo.com/api/manifest/hls_variant'])
        self.assertNotIn('PRIVATE', str(result))
        self.assertNotIn('SECRET', str(result))

    def test_player_video_details_are_read_from_the_documented_fields(self):
        details = b'\x0a\x0bhw2iFtnTygA\x7a\x05Title'
        result = inspect_body(b'\x5a' + bytes([len(details)]) + details, '/youtubei/v1/player')
        self.assertEqual(result['videoId'], 'hw2iFtnTygA')
        self.assertEqual(result['title'], 'Title')


if __name__ == '__main__':
    unittest.main()
