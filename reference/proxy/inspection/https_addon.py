"""Inspection locale YouTube et filtre expérimental par identifiant vidéo."""
import asyncio
import ipaddress
import importlib
import json
import os
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

from mitmproxy import http

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent))
import api_inspect
inspect_body = importlib.reload(api_inspect).inspect_body
from ump_inspect import UmpInspector
from ump_filter import UmpGate
from video_filter_config import read_config
from navigation_inspect import inspect_navigation
from onesie_inspect import vault
from auto_video_filter import selector
import ad_program
ad_program = importlib.reload(ad_program)
from proxy import INSPECT_HOSTS, inspect_host

API_PATHS = {'player', 'get_watch', 'browse', 'next', 'search', 'config', 'log_event', 'guide', 'reel/reel_watch_sequence'}


def ad_program_mode():
    try:
        return (ROOT / 'ad-program-mode.txt').read_text().strip()
    except OSError:
        return 'off'


class Inspector:
    def __init__(self):
        self.clients = {}
        self.directory = ROOT / 'https-responses'
        self.directory.mkdir(mode=0o700, exist_ok=True)
        self.log_path = ROOT / 'https-events.jsonl'
        self.log_path.touch(mode=0o600, exist_ok=True)
        self.log_path.chmod(0o600)

    def record(self, event, **fields):
        row = {'time': datetime.now(timezone.utc).isoformat(), 'event': event, **fields}
        with self.log_path.open('a') as handle:
            handle.write(json.dumps(row, ensure_ascii=False) + '\n')

    def client_info(self, client):
        # La connexion survit au rechargement du script par mitmproxy.
        return getattr(client, '_youtube_poc', self.clients.get(client.id, {}))

    def note_navigation(self, flow, path, navigation):
        flow.metadata['navigation'] = navigation
        info = flow.metadata['poc']
        self.record('navigation_request', **info, request_id=flow.id, path=path, navigation=navigation)
        config = read_config()
        if config['enabled'] and config.get('mode') == 'auto':
            state = selector.consider(info.get('client_ip'), navigation, config.get('windowSeconds', 45), flow.id)
            if state:
                self.record('auto_video_selected', **info, path=path, auto_selection=state,
                            reason='Cible temporaire déduite de la navigation YouTube')

    def http_connect(self, flow):
        if not inspect_host(flow.request.host, True) or flow.request.port != 443:
            flow.response = http.Response.make(403, b'YouTube API hosts only')
            return
        self.clients[flow.client_conn.id] = {
            'client_ip': flow.request.headers.pop('X-Poc-Client-IP', '127.0.0.1'),
            'flow_id': flow.request.headers.pop('X-Poc-Flow-ID', ''),
            'host': flow.request.host,
        }
        flow.client_conn._youtube_poc = self.clients[flow.client_conn.id]

    async def server_connect(self, data):
        host, port = data.server.address
        if not inspect_host(host, True) or port != 443:
            data.server.error = 'Destination hors périmètre'
            return
        try:
            addresses = await asyncio.get_running_loop().getaddrinfo(host, port, type=socket.SOCK_STREAM)
            if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
                data.server.error = 'Destination non publique'
        except OSError:
            data.server.error = 'Échec DNS'

    def client_disconnected(self, client):
        self.clients.pop(client.id, None)

    def tls_failed_client(self, data):
        error = (data.context.client.error or '').lower()
        category = next((code for code in ('unknown ca', 'bad certificate', 'certificate unknown',
                                          'unsupported certificate', 'handshake failure',
                                          'connection closed', 'connection reset') if code in error), 'other')
        self.record('tls_client_error', **self.client_info(data.context.client),
                    tls_alert=category, tls_detail=error[:400],
                    reason='Le client a refusé ou interrompu TLS ; vérifier la confiance du certificat et le pinning')

    def request(self, flow):
        if not inspect_host(flow.request.host, True) or flow.request.port != 443:
            flow.response = http.Response.make(403, b'Outside inspection scope')
            return
        flow.metadata['poc'] = {**self.client_info(flow.client_conn), 'host': flow.request.host}
        flow.metadata['poc_request_at'] = time.perf_counter()
        request_path = urlsplit(flow.request.path).path
        client_ip = flow.metadata['poc'].get('client_ip', '')
        if flow.request.host in INSPECT_HOSTS:
            if request_path == '/youtubei/v1/log_event' and not vault.ready(client_ip):
                # Demander la configuration courante au lieu de sa validation en cache.
                flow.request.headers.pop('x-youtube-hot-hash-data', None)
            navigation = inspect_navigation(flow.request.get_content(strict=False) or b'', request_path)
            if navigation:
                self.note_navigation(flow, request_path, navigation)
        if flow.request.host not in INSPECT_HOSTS:
            if request_path == '/initplayback' and flow.request.method == 'POST':
                navigation = vault.inspect(flow.request.get_content(strict=False) or b'', client_ip)
                if navigation:
                    if navigation.get('onesieStatus') == 'key_unavailable':
                        # Un redémarrage de l'app peut changer la clé malgré son cache hot-config.
                        vault.keys = {k: v for k, v in vault.keys.items() if k[0] != client_ip}
                    self.note_navigation(flow, request_path, navigation)
            url = urlsplit(flow.request.path)
            params = parse_qs(url.query)
            # Valeurs techniques uniquement ; aucune URL signée ni clé de lecture.
            technical = {key: values[0][:100] for key, values in params.items()
                         if key in ('itag', 'mime', 'source', 'clen', 'dur', 'range', 'live', 'oad')}
            self.record('media_request', **flow.metadata['poc'], request_id=flow.id,
                        path=url.path, method=flow.request.method, media_info=technical,
                        query_keys=sorted(params.keys()), request_bytes=len(flow.request.raw_content or b''),
                        request_content_type=flow.request.headers.get('content-type', '').split(';')[0])

    def responseheaders(self, flow):
        flow.metadata['poc_headers_at'] = time.perf_counter()
        path = urlsplit(flow.request.path).path
        endpoint = path.removeprefix('/youtubei/v1/')
        if not path.startswith('/youtubei/v1/') or endpoint not in API_PATHS:
            flow.response.stream = True
        else:
            try:
                length = int(flow.response.headers.get('content-length', '0') or '0')
            except ValueError:
                length = 4 * 1024 * 1024 + 1
            if length > 4 * 1024 * 1024:
                flow.response.stream = True
        is_media_host = flow.request.host not in INSPECT_HOSTS
        is_ump = (flow.response.headers.get('content-type', '').split(';')[0].strip().lower() == 'application/vnd.yt-ump'
                  and flow.response.headers.get('content-encoding', 'identity').lower() == 'identity')
        config = read_config()
        automatic = config.get('mode') == 'auto'
        auto_state = selector.active(flow.metadata.get('poc', {}).get('client_ip')) if automatic else None
        target_id = auto_state['videoId'] if auto_state else config['videoId'] if not automatic else None
        strict = is_media_host and config['enabled'] and (bool(auto_state) if automatic else True)
        # Inclut /initplayback : il peut transporter le début des médias.
        gate = UmpGate(target_id) if strict and is_ump and target_id else None
        reject_unknown = strict and not gate and 200 <= flow.response.status_code < 300 and flow.response.status_code != 204
        if gate or reject_unknown:
            for name in ('content-length', 'content-md5', 'digest', 'etag', 'content-range'):
                flow.response.headers.pop(name, None)
            if flow.request.is_http11:
                flow.response.headers['transfer-encoding'] = 'chunked'
            elif flow.request.is_http10:
                flow.response.headers['connection'] = 'close'
            flow.metadata['poc_filter_active'] = True
        if gate:
            flow.metadata['ump_gate'] = gate
        if is_media_host and is_ump:
            observer = UmpInspector()
            flow.metadata['ump_observer'] = observer
            program_mode = ad_program_mode()
            program = None
            if path == '/initplayback' and program_mode in ('observe', 'remove'):
                key = ad_program.request_key(flow.request.get_content(strict=False) or b'',
                                             flow.metadata.get('poc', {}).get('client_ip'), vault)
                program = ad_program.AdProgramStream(key, program_mode == 'remove')
                flow.metadata['ad_program_stream'] = program
                # Les changements éventuels ne sont connus qu'après lecture de l'enveloppe.
                if program_mode == 'remove':
                    for name in ('content-length', 'content-md5', 'digest', 'etag', 'content-range'):
                        flow.response.headers.pop(name, None)
                    if flow.request.is_http11:
                        flow.response.headers['transfer-encoding'] = 'chunked'

            def observe_chunk(chunk):
                final_chunk = not chunk
                try:
                    for header in observer.feed(chunk):
                        self.record('ump_media_header', **flow.metadata.get('poc', {}),
                                    request_id=flow.id, path=path, ump_header=header)
                except Exception:
                    observer.error = 'Analyse des identifiants interrompue'
                if program:
                    chunk = program.feed(chunk)
                    for event in program.events:
                        if 'poc_request_at' in flow.metadata:
                            event['sinceRequestMs'] = round((time.perf_counter() - flow.metadata['poc_request_at']) * 1000, 1)
                            event['upstreamHeadersMs'] = round((flow.metadata['poc_headers_at'] - flow.metadata['poc_request_at']) * 1000, 1)
                        self.record('ad_program', **flow.metadata.get('poc', {}),
                                    request_id=flow.id, path=path, mode=program_mode, **event)
                    program.events.clear()
                if gate:
                    result = gate.feed(chunk) if chunk or final_chunk else b''
                    for decision in gate.take_events():
                        self.record('ump_filter_decision', **flow.metadata.get('poc', {}),
                                    request_id=flow.id, path=path, target_video_id=target_id, **decision)
                    # En HTTP/1 chunked, b'' au milieu serait un chunk terminal.
                    # Une liste vide signifie réellement « aucun fragment à envoyer ».
                    return result if result else []
                return [] if reject_unknown or not chunk else chunk

            flow.response.stream = observe_chunk
        if reject_unknown:
            counters = {'targetVideoId': target_id, 'receivedBytes': 0,
                        'forwardedBytes': 0, 'withheldBytes': 0,
                        'reason': 'Format média ou configuration non reconnu ; réponse retenue'}
            flow.metadata['unknown_media_filter'] = counters
            self.record('ump_filter_decision', **flow.metadata.get('poc', {}),
                        request_id=flow.id, path=path, decision='blocked_unknown', reason=counters['reason'])

            def discard_chunk(chunk):
                counters['receivedBytes'] += len(chunk)
                counters['withheldBytes'] += len(chunk)
                return []

            flow.response.stream = discard_chunk

    def response(self, flow):
        if not inspect_host(flow.request.host, True):
            return
        path = urlsplit(flow.request.path).path
        info = {**flow.metadata.get('poc', {}), 'host': flow.request.host,
                'request_id': flow.id, 'path': path, 'method': flow.request.method,
                'status': flow.response.status_code,
                'client_http_version': flow.request.http_version,
                'server_ip': flow.server_conn.peername[0] if flow.server_conn.peername else None,
                'content_type': flow.response.headers.get('content-type', '').split(';')[0],
                'modified': bool(flow.metadata.get('poc_filter_active'))}
        body = flow.response.get_content(strict=False)
        if body and path in ('/youtubei/v1/player', '/youtubei/v1/get_watch'):
            program_mode = ad_program_mode()
            if program_mode in ('observe', 'remove'):
                rewritten, reports = ad_program.rewrite_api(body, path, program_mode == 'remove')
                self.record('ad_program', **flow.metadata.get('poc', {}), request_id=flow.id,
                            path=path, mode=program_mode, status='api', players=reports,
                            modified=rewritten != body)
                if rewritten != body:
                    flow.response.content = rewritten
                    for name in ('content-md5', 'digest', 'etag'):
                        flow.response.headers.pop(name, None)
                    info['modified'] = True
        if 'ad_program_stream' in flow.metadata:
            info['modified'] = info['modified'] or flow.metadata['ad_program_stream'].modified
        info['body_bytes'] = len(body) if body is not None else None
        if body and flow.request.host in INSPECT_HOSTS and vault.capture(body, info.get('client_ip', '')):
            self.record('navigation_decoder_ready', **flow.metadata.get('poc', {}),
                        reason='Configuration de lecture reconnue ; décodeur local prêt')
        if 'ump_observer' in flow.metadata:
            info['ump'] = flow.metadata['ump_observer'].summary()
            info['body_bytes'] = info['ump']['bytesObserved']
        if 'ump_gate' in flow.metadata:
            info['video_filter'] = flow.metadata['ump_gate'].summary()
        elif 'unknown_media_filter' in flow.metadata:
            info['video_filter'] = flow.metadata['unknown_media_filter']
        if body and len(body) <= 4 * 1024 * 1024 and path in ('/youtubei/v1/player', '/youtubei/v1/get_watch'):
            info['analysis'] = inspect_body(body, path)
            file = self.directory / (flow.id + '.bin')
            fd = os.open(file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'wb') as handle:
                handle.write(body)
            info['local_body_file'] = file.name
        self.record('api_response' if flow.request.host in INSPECT_HOSTS else 'media_response', **info)

    def error(self, flow):
        extra = {}
        if 'ump_gate' in flow.metadata:
            extra['video_filter'] = flow.metadata['ump_gate'].summary()
        elif 'unknown_media_filter' in flow.metadata:
            extra['video_filter'] = flow.metadata['unknown_media_filter']
        self.record('api_error', **self.client_info(flow.client_conn),
                    path=urlsplit(flow.request.path).path if flow.request else None,
                    client_http_version=flow.request.http_version if flow.request else None,
                    reason='Échec de connexion ou de transport HTTPS', **extra)


addons = [Inspector()]
