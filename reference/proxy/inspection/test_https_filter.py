"""Filter integration with HTTP callbacks, without network access or captured files."""
import unittest
from unittest.mock import patch
from mitmproxy import http
from mitmproxy.test.tflow import tflow
from inspection import https_addon as addon
from inspection.test_ump_filter import TARGET, OTHER, header, media


class AddonTests(unittest.TestCase):
    def setup_flow(self, path='/videoplayback', content_type='application/vnd.yt-ump', enabled=True, host='test.googlevideo.com'):
        flow = tflow(resp=True)
        flow.request = http.Request.make('POST', 'https://' + host + path)
        flow.response = http.Response.make(200, b'', {'Content-Type': content_type, 'Content-Length': '1000'})
        flow.response.headers['content-length'] = '1000'
        flow.metadata['poc'] = {'client_ip': '192.0.2.20', 'host': host}
        inspector = addon.Inspector.__new__(addon.Inspector)
        events = []
        inspector.record = lambda name, **kw: events.append({'event': name, **kw})
        with patch.object(addon, 'read_config', return_value={'enabled': enabled, 'videoId': TARGET}):
            inspector.responseheaders(flow)
        return flow, inspector, events

    def test_initplayback_and_videoplayback_filter_and_keep_upstream_observation(self):
        for path in ('/initplayback', '/videoplayback'):
            flow, inspector, events = self.setup_flow(path)
            target = header(1) + media(1, b'target')
            other = header(2, OTHER) + media(2, b'foreign')
            callback = flow.response.stream
            self.assertEqual(callback(target + other), target)
            self.assertEqual(callback(b''), [])
            self.assertNotIn('content-length', flow.response.headers)
            self.assertEqual(flow.response.headers['transfer-encoding'], 'chunked')
            seen = [e['ump_header']['videoId'] for e in events if e['event'] == 'ump_media_header']
            self.assertEqual(seen, [TARGET, OTHER])
            inspector.response(flow)
            self.assertEqual(events[-1]['video_filter']['withheldBytes'], len(other))
            self.assertEqual(events[-1]['video_filter']['forwardedBytes'], len(target))

    def test_unknown_media_format_is_fully_withheld(self):
        flow, _, events = self.setup_flow(content_type='video/mp4')
        self.assertEqual(flow.response.stream(b'unknown video bytes'), [])
        self.assertEqual(flow.metadata['unknown_media_filter']['withheldBytes'], 19)
        self.assertEqual(events[0]['decision'], 'blocked_unknown')

    def test_empty_fragments_do_not_emit_an_http1_terminal_chunk(self):
        flow, _, _ = self.setup_flow()
        callback = flow.response.stream
        self.assertEqual(callback(header(2, OTHER) + media(2, b'foreign')), [])
        target = header(1) + media(1, b'target')
        self.assertEqual(callback(target[:1]), [])
        self.assertEqual(callback(target[1:]), target)
        self.assertEqual(callback(b''), [])

    def test_disable_restores_original_chunks_and_headers(self):
        flow, _, _ = self.setup_flow(enabled=False)
        chunk = header(2, OTHER) + media(2, b'foreign')
        self.assertIs(flow.response.stream(chunk), chunk)
        self.assertEqual(flow.response.headers['content-length'], '1000')

    def test_api_responses_are_not_filtered(self):
        flow, _, _ = self.setup_flow(path='/youtubei/v1/player', content_type='application/json', host='youtubei.googleapis.com')
        self.assertNotIn('poc_filter_active', flow.metadata)
        self.assertEqual(flow.response.headers['content-length'], '1000')

    def test_automatic_navigation_ignores_ad_then_expires(self):
        import tempfile
        from pathlib import Path
        from inspection.auto_video_filter import AutoSelector
        clock = [1000.0]
        with tempfile.TemporaryDirectory() as directory:
            selector = AutoSelector(Path(directory) / 'auto.json', clock=lambda: clock[0])
            inspector = addon.Inspector.__new__(addon.Inspector)
            inspector.record = lambda *args, **kwargs: None
            flow = tflow(resp=True)
            flow.metadata['poc'] = {'client_ip': 'phone'}
            config = {'enabled': True, 'mode': 'auto', 'videoId': OTHER, 'windowSeconds': 45}
            with patch.object(addon, 'selector', selector), patch.object(addon, 'read_config', return_value=config):
                inspector.note_navigation(flow, '/next', {'eligible': True, 'videoId': TARGET, 'source': 'next'})
                inspector.note_navigation(flow, '/next', {'eligible': False, 'videoId': OTHER, 'isAdPlayback': 1})
                for expired in (False, True):
                    flow.request = http.Request.make('POST', 'https://test.googlevideo.com/videoplayback')
                    flow.response = http.Response.make(200, b'', {'content-type': 'application/vnd.yt-ump'})
                    flow.metadata = {'poc': {'client_ip': 'phone'}}
                    inspector.responseheaders(flow)
                    raw = header(1) + media(1, b'target') + header(2, OTHER) + media(2, b'ad')
                    actual = flow.response.stream(raw)
                    self.assertEqual(actual, raw if expired else header(1) + media(1, b'target'))
                    clock[0] += 46

    def test_ad_program_stream_rewrites_control_but_passes_all_media(self):
        from inspection.test_ad_program import encrypted_pair, KEY
        flow = tflow(resp=True)
        flow.request = http.Request.make('POST', 'https://test.googlevideo.com/initplayback')
        flow.response = http.Response.make(200, b'', {'content-type': 'application/vnd.yt-ump', 'content-length': '100'})
        flow.metadata['poc'] = {'client_ip': 'phone'}
        inspector = addon.Inspector.__new__(addon.Inspector)
        events = []
        inspector.record = lambda name, **kw: events.append({'event': name, **kw})
        with patch.object(addon, 'ad_program_mode', return_value='remove'), \
             patch.object(addon.ad_program, 'request_key', return_value=KEY), \
             patch.object(addon, 'read_config', return_value={'enabled': False, 'videoId': TARGET}):
            inspector.responseheaders(flow)
            raw = encrypted_pair()
            media_bytes = header(2, OTHER) + media(2, b'all media passes')
            self.assertEqual(flow.response.stream(raw[:20]), [])
            output = flow.response.stream(raw[20:] + media_bytes)
            self.assertTrue(output.endswith(media_bytes))
            self.assertNotEqual(output, raw + media_bytes)
            self.assertEqual(flow.response.stream(b''), [])
            inspector.response(flow)
        self.assertTrue(events[-1]['modified'])
        self.assertTrue(any(e['event'] == 'ad_program' and e.get('modified') for e in events))
        self.assertNotIn('video_filter', events[-1])


if __name__ == '__main__':
    unittest.main()
