#!/usr/bin/env python3
"""Journal local du test YouTube et repères manuels de publicités."""

import hashlib
import json
import math
import os
import sys
import threading
import uuid
from collections import Counter
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from proxy import AD_DOMAINS, RELATED_DOMAINS, INSPECT_HOSTS
from inspection.video_filter_config import read_config as read_video_filter, write_config as write_video_filter

PHONE_IP = os.environ.get("POC_PHONE_IP", "192.0.2.20")
PORT = 8878
PHONE_START = "2026-10-18T12:26:30+00:00"
MARKER_LOCK = threading.Lock()
ROW_LOCK = threading.Lock()
FILTER_LOCK = threading.Lock()
LOOKBACK_SECONDS = 30


def read_records(name):
    path = ROOT / name
    records = []
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                # L'écriture d'une ligne peut être en cours ; prochain poll.
                continue
    return records


def video_identities():
    try:
        return json.loads((ROOT / 'inspection/video-identities.json').read_text())
    except (OSError, ValueError):
        return {}


def ad_program_mode():
    try:
        return (ROOT / 'inspection/ad-program-mode.txt').read_text().strip()
    except OSError:
        return 'off'


def video_filter_state():
    config = read_video_filter()
    try:
        state = json.loads((ROOT / 'inspection/auto-video-state.json').read_text()).get(PHONE_IP)
    except (OSError, ValueError):
        state = None
    remaining = max(0, math.ceil(state['expiresAtEpoch'] - datetime.now(timezone.utc).timestamp())) if state else 0
    return {**config, 'autoState': state, 'remainingSeconds': remaining}


def ad_intervals(markers):
    intervals = {}
    for marker in markers:
        if marker.get("event") == "ad_start":
            intervals[marker["ad_id"]] = {
                "id": marker["ad_id"], "start": marker["time"], "end": None,
                "modeAtStart": marker.get("mode"),
            }
        elif marker.get("event") == "ad_end" and marker.get("ad_id") in intervals:
            intervals[marker["ad_id"]]["end"] = marker["time"]
    return list(intervals.values())


def ad_analysis(events, markers, now=None):
    now = now or datetime.now(timezone.utc)
    intervals = ad_intervals(markers)
    phone_start = datetime.fromisoformat(PHONE_START)
    windows = [
        (max(phone_start, datetime.fromisoformat(item["start"]) - timedelta(seconds=LOOKBACK_SECONDS)),
         datetime.fromisoformat(item["end"]) if item["end"] else now)
        for item in intervals
    ]
    allowed = [
        (event, datetime.fromisoformat(event["time"])) for event in events
        if event.get("event") == "tunnel" and event.get("host")
        and phone_start <= datetime.fromisoformat(event["time"]) <= now
    ]
    outside = Counter(
        event["host"] for event, timestamp in allowed
        if not any(start <= timestamp <= end for start, end in windows)
    )
    for item, (window_start, window_end) in zip(intervals, windows):
        start = datetime.fromisoformat(item["start"])
        counts = {}
        for event, timestamp in allowed:
            if not window_start <= timestamp <= window_end:
                continue
            host = event["host"]
            entry = counts.setdefault(host, {
                "host": host, "before": 0, "during": 0, "outsideMarkedWindows": outside[host],
                "lastSeen": event["time"],
            })
            entry["before" if timestamp < start else "during"] += 1
            entry["lastSeen"] = max(entry["lastSeen"], event["time"])
        item["windowStart"] = window_start.isoformat()
        item["windowEnd"] = window_end.isoformat()
        item["candidates"] = sorted(counts.values(), key=lambda row: (-row["during"], -row["before"], row["host"]))
    return intervals


def set_ad_visible(visible):
    with MARKER_LOCK:
        markers = read_records("ad-markers.jsonl")
        active = next((item for item in reversed(ad_intervals(markers)) if item["end"] is None), None)
        if visible and active or not visible and not active:
            return active["id"] if active else None
        ad_id = str(uuid.uuid4()) if visible else active["id"]
        marker = {
            "time": datetime.now(timezone.utc).isoformat(),
            "event": "ad_start" if visible else "ad_end", "ad_id": ad_id,
            "mode": (ROOT / "mode.txt").read_text().strip(), "source": "dashboard",
        }
        with (ROOT / "ad-markers.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(marker, ensure_ascii=False) + "\n")
        return ad_id


def identified_events(events):
    """IDs stables à l'ajout de logs, distincts même pour deux lignes identiques."""
    occurrences = Counter()
    result = []
    for event in events:
        digest = hashlib.sha256(json.dumps(event, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        occurrences[digest] += 1
        result.append({**event, "id": f"{digest}:{occurrences[digest]}"})
    return result


def suspected_rows(markers):
    selected = {}
    for marker in markers:
        if marker.get("suspected"):
            selected[marker["eventId"]] = {**marker["connection"], "markedAt": marker["time"]}
        else:
            selected.pop(marker.get("eventId"), None)
    return list(selected.values())


def set_row_suspected(event_id, suspected):
    with ROW_LOCK:
        connection = next((event for event in identified_events(read_records("events.jsonl"))
                           if event["id"] == event_id and event.get("host")), None)
        if connection is None:
            raise ValueError("Connexion inconnue")
        selected = suspected_rows(read_records("row-markers.jsonl"))
        if any(row["id"] == event_id for row in selected) == suspected:
            return
        marker = {"time": datetime.now(timezone.utc).isoformat(), "eventId": event_id,
                  "suspected": suspected, "connection": connection, "source": "dashboard"}
        with (ROOT / "row-markers.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(marker, ensure_ascii=False) + "\n")


def snapshot():
    now = datetime.now(timezone.utc)
    records = read_records("events.jsonl")
    events = identified_events([record for record in records if record.get("event") not in ("flow_progress", "flow_closed")])
    flows = {}
    last_start = max((record["time"] for record in records if record.get("event") == "started"), default="")
    for record in records:
        if record.get("flow_id"):
            state = "closed" if record["event"] == "flow_closed" else "interrupted" if record["time"] < last_start else "open"
            flows[record["flow_id"]] = {**record, "state": state}
    for event in events:
        if event.get("flow_id") in flows:
            event["flow"] = flows[event["flow_id"]]
    markers = read_records("ad-markers.jsonl")
    intervals = ad_analysis(events, markers, now)
    active = next((item["id"] for item in reversed(intervals) if item["end"] is None), None)
    https_mode = ((ROOT / "inspection/https-mode.txt").read_text().strip()
                  if (ROOT / "inspection/https-mode.txt").exists() else "off")
    return {
        "updatedAt": now.isoformat(), "phoneStart": PHONE_START, "phoneIp": PHONE_IP,
        "mode": (ROOT / "mode.txt").read_text().strip(),
        "adDomains": AD_DOMAINS, "loggedDomains": RELATED_DOMAINS,
        "events": events, "observations": read_records("observations.jsonl"),
        "adIntervals": intervals, "activeAdId": active, "lookbackSeconds": LOOKBACK_SECONDS,
        "suspectedRows": suspected_rows(read_records("row-markers.jsonl")),
        "httpsInspection": {
            "mode": https_mode,
            "hosts": INSPECT_HOSTS + (("*.googlevideo.com",) if https_mode == "observe-media" else ()),
            "events": read_records("inspection/https-events.jsonl")[-500:],
            "videoFilter": video_filter_state(),
            "videoIdentities": video_identities(),
            "adProgramMode": ad_program_mode(),
        },
    }


class Handler(BaseHTTPRequestHandler):
    def host_allowed(self):
        return self.headers.get("Host") in (f"127.0.0.1:{PORT}", f"localhost:{PORT}")

    def do_POST(self):
        origins = (f"http://127.0.0.1:{PORT}", f"http://localhost:{PORT}")
        if not self.host_allowed() or self.headers.get("Origin") not in origins:
            self.send_error(403)
            return
        path = urlsplit(self.path).path
        if path not in ("/api/ad-visibility", "/api/row-suspicion", "/api/video-filter", "/api/ad-program"):
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096 or self.headers.get_content_type() != "application/json":
                raise ValueError("Requête invalide")
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError("Objet attendu")
            if path == "/api/ad-visibility":
                if type(body.get("visible")) is not bool:
                    raise ValueError("visible doit être un booléen")
                ad_id = set_ad_visible(body["visible"])
            elif path == '/api/video-filter':
                with FILTER_LOCK:
                    if body.get('enabled') and ad_program_mode() == 'remove':
                        raise ValueError('Désactiver le retrait de programmation avant de filtrer les médias')
                    if body.get('enabled') and (ROOT / 'inspection/https-mode.txt').read_text().strip() != 'observe-media':
                        raise ValueError('Inspection des médias inactive')
                    write_video_filter(body.get('enabled'), body.get('videoId'),
                                       body.get('mode', 'manual'), body.get('windowSeconds', 45))
            elif path == '/api/ad-program':
                mode = body.get('mode')
                if mode not in ('off', 'observe', 'remove'):
                    raise ValueError('Mode invalide')
                with FILTER_LOCK:
                    if mode == 'remove':
                        if (ROOT / 'inspection/https-mode.txt').read_text().strip() != 'observe-media':
                            raise ValueError('Inspection inactive')
                        config = read_video_filter()
                        write_video_filter(False, config['videoId'], config.get('mode', 'auto'), config.get('windowSeconds', 45))
                    path_mode = ROOT / 'inspection/ad-program-mode.txt'
                    temporary = path_mode.with_suffix('.tmp')
                    temporary.write_text(mode + '\n')
                    temporary.replace(path_mode)
            else:
                if type(body.get("suspected")) is not bool or not isinstance(body.get("eventId"), str):
                    raise ValueError("Sélection invalide")
                set_row_suspected(body["eventId"], body["suspected"])
        except (ValueError, UnicodeDecodeError):
            self.send_error(400)
            return
        payload = snapshot()
        if path == "/api/ad-visibility":
            payload["markedAdId"] = ad_id
        self.respond(json.dumps(payload, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def do_GET(self):
        if not self.host_allowed():
            self.send_error(403)
            return
        path = urlsplit(self.path).path
        if path == "/":
            body = (ROOT / "dashboard/dist/index.html").read_bytes()
            content_type = "text/html; charset=utf-8"
        elif path == "/api/snapshot":
            body = json.dumps(snapshot(), ensure_ascii=False).encode("utf-8")
            content_type = "application/json; charset=utf-8"
        elif path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return
        else:
            self.send_error(404)
            return
        self.respond(body, content_type)

    def respond(self, body, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    print(f"Journal local : http://127.0.0.1:{PORT}", flush=True)
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
