import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import server


def event(at, host="media.googlevideo.com", kind="tunnel"):
    return {"time": f"2026-10-18T12:{at}+00:00", "event": kind, "host": host, "mode": "block"}


def marker(at, kind, ad_id="one"):
    return {"time": f"2026-10-18T12:{at}+00:00", "event": kind, "ad_id": ad_id, "mode": "block"}


class CorrelationTests(unittest.TestCase):
    def test_window_counts_only_allowed_and_keeps_outside_context(self):
        events = [event("44:59"), event("45:00"), event("45:29"), event("45:30"),
                  event("45:40"), event("45:41"), event("45:35", "ad.doubleclick.net", "blocked")]
        markers = [marker("45:30", "ad_start"), marker("45:40", "ad_end")]
        data = server.ad_analysis(events, markers, datetime.fromisoformat("2026-10-18T12:46:00+00:00"))
        self.assertEqual(len(data[0]["candidates"]), 1)
        candidate = data[0]["candidates"][0]
        self.assertEqual((candidate["before"], candidate["during"], candidate["outsideMarkedWindows"]), (2, 2, 2))

    def test_overlapping_prefetch_windows_do_not_count_as_outside(self):
        markers = [marker("45:30", "ad_start"), marker("45:40", "ad_end"),
                   marker("46:00", "ad_start", "two")]
        events = [event("45:35"), event("46:05"), event("46:12")]
        data = server.ad_analysis(events, markers, datetime.fromisoformat("2026-10-18T12:46:10+00:00"))
        first, second = [item["candidates"][0] for item in data]
        self.assertEqual(first["during"], 1)
        self.assertEqual((second["before"], second["during"]), (1, 1))
        self.assertEqual(second["outsideMarkedWindows"], 0)


class AnnotationAPITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        (root / "mode.txt").write_text("block\n")
        (root / "events.jsonl").write_text("")
        self.root_patch = patch.object(server, "ROOT", root)
        self.root_patch.start()
        self.http = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        self.port_patch = patch.object(server, "PORT", self.http.server_address[1])
        self.port_patch.start()
        self.base = f"http://127.0.0.1:{server.PORT}"
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()
        self.port_patch.stop()
        self.root_patch.stop()
        self.temp.cleanup()

    def post(self, payload, origin=None, path="/api/ad-visibility"):
        request = urllib.request.Request(
            self.base + path, json.dumps(payload).encode(),
            {"Content-Type": "application/json", "Origin": origin or self.base}, method="POST",
        )
        with urllib.request.urlopen(request) as response:
            return json.load(response)

    def test_checkbox_persists_is_idempotent_and_supports_back_to_back_ads(self):
        first = self.post({"visible": True})
        same = self.post({"visible": True})
        self.assertEqual(first["activeAdId"], same["activeAdId"])
        with urllib.request.urlopen(self.base + "/api/snapshot") as response:
            reloaded = json.load(response)
        self.assertEqual(reloaded["activeAdId"], first["activeAdId"])
        ended = self.post({"visible": False})
        self.assertIsNone(ended["activeAdId"])
        self.assertIsNotNone(ended["adIntervals"][0]["end"])
        second = self.post({"visible": True})
        self.assertNotEqual(second["activeAdId"], first["activeAdId"])
        self.assertEqual(len(second["adIntervals"]), 2)
        self.assertEqual(len(server.read_records("ad-markers.jsonl")), 3)
        self.assertEqual((server.ROOT / "mode.txt").read_text(), "block\n")

    def test_rejects_cross_origin_and_invalid_checkbox_values(self):
        for payload, origin, status in [({"visible": True}, "https://other.example", 403),
                                        ({"visible": "yes"}, self.base, 400)]:
            with self.assertRaises(urllib.error.HTTPError) as error:
                self.post(payload, origin)
            self.assertEqual(error.exception.code, status)
            error.exception.close()
        self.assertEqual(server.read_records("ad-markers.jsonl"), [])

    def test_row_selection_is_exact_persistent_and_reversible(self):
        rows = [event("46:00"), event("46:00"), event("46:01", "ad.doubleclick.net", "blocked")]
        log = server.ROOT / "events.jsonl"
        original = "".join(json.dumps(row) + "\n" for row in rows)
        log.write_text(original)
        events = server.snapshot()["events"]
        self.assertNotEqual(events[0]["id"], events[1]["id"])
        payload = {"eventId": events[1]["id"], "suspected": True}
        selected = self.post(payload, path="/api/row-suspicion")
        self.post(payload, path="/api/row-suspicion")
        self.assertEqual([row["id"] for row in selected["suspectedRows"]], [events[1]["id"]])
        self.assertEqual(len(server.read_records("row-markers.jsonl")), 1)
        with log.open("a") as handle:
            handle.write(json.dumps(event("46:03")) + "\n")
        with urllib.request.urlopen(self.base + "/api/snapshot") as response:
            reloaded = json.load(response)
        self.assertEqual(reloaded["events"][:3], events)
        self.assertEqual(reloaded["suspectedRows"], selected["suspectedRows"])
        marked_blocked = self.post({"eventId": events[2]["id"], "suspected": True}, path="/api/row-suspicion")
        self.assertEqual(len(marked_blocked["suspectedRows"]), 2)
        unchecked = self.post({"eventId": events[1]["id"], "suspected": False}, path="/api/row-suspicion")
        self.assertEqual([row["event"] for row in unchecked["suspectedRows"]], ["blocked"])
        self.assertTrue(log.read_text().startswith(original))
        self.assertEqual((server.ROOT / "mode.txt").read_text(), "block\n")

    def test_row_selection_rejects_unknown_rows_invalid_values_and_cross_origin(self):
        for payload, origin, status in [({"eventId": "unknown", "suspected": True}, self.base, 400),
                                        ({"eventId": "unknown", "suspected": "yes"}, self.base, 400),
                                        ({"eventId": "unknown", "suspected": True}, "https://other.example", 403)]:
            with self.assertRaises(urllib.error.HTTPError) as error:
                self.post(payload, origin, path="/api/row-suspicion")
            self.assertEqual(error.exception.code, status)
            error.exception.close()
        self.assertEqual(server.read_records("row-markers.jsonl"), [])

    def test_flow_updates_enrich_one_connection_without_changing_its_id(self):
        opened = {**event("46:00"), "flow_id": "flow-one", "bytes_from_server": 0}
        log = server.ROOT / "events.jsonl"
        log.write_text(json.dumps(opened) + "\n")
        before = server.snapshot()["events"][0]
        self.post({"eventId": before["id"], "suspected": True}, path="/api/row-suspicion")
        with log.open("a") as handle:
            for kind, received in [("flow_progress", 1200), ("flow_closed", 2400)]:
                handle.write(json.dumps({**opened, "event": kind, "bytes_from_server": received}) + "\n")
        after = server.snapshot()
        self.assertEqual(len(after["events"]), 1)
        self.assertEqual(after["events"][0]["id"], before["id"])
        self.assertEqual(after["events"][0]["flow"]["bytes_from_server"], 2400)
        self.assertEqual(after["events"][0]["flow"]["state"], "closed")
        self.assertEqual(after["suspectedRows"][0]["id"], before["id"])

    def test_ad_program_setting_disables_media_filter_and_rejects_bad_mode(self):
        (server.ROOT / 'inspection').mkdir()
        (server.ROOT / 'inspection/https-mode.txt').write_text('observe-media\n')
        config = {'enabled': True, 'mode': 'auto', 'windowSeconds': 45, 'videoId': 'thbQYUvfLFQ'}
        with patch.object(server, 'read_video_filter', return_value=config), \
             patch.object(server, 'write_video_filter') as write_filter:
            result = self.post({'mode': 'remove'}, path='/api/ad-program')
            write_filter.assert_called_once_with(False, 'thbQYUvfLFQ', 'auto', 45)
            self.assertEqual(result['httpsInspection']['adProgramMode'], 'remove')
            for payload, path in [({'mode': 'wrong'}, '/api/ad-program'),
                                  ({'enabled': True, 'videoId': 'thbQYUvfLFQ'}, '/api/video-filter')]:
                with self.assertRaises(urllib.error.HTTPError) as error:
                    self.post(payload, path=path)
                self.assertEqual(error.exception.code, 400)
                error.exception.close()
            self.assertEqual(self.post({'mode': 'observe'}, path='/api/ad-program')['httpsInspection']['adProgramMode'], 'observe')


if __name__ == "__main__":
    unittest.main()
