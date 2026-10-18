"""Filtre UMP local : seuls les médias associés à target_id sont transmis.

Le préfixe de chaque bloc est retenu jusqu'à sa décision. Les gros médias
autorisés sont ensuite relayés sans stockage ; les autres sont consommés.
Les en-têtes et leur association sont propres à chaque réponse HTTP.
"""
import re
from collections import Counter

try:
    from .ump_inspect import media_header, ump_uint
except ImportError:
    from ump_inspect import media_header, ump_uint

# Contrôle du protocole, pas des octets audio/vidéo. Types inconnus : refusés.
CONTROL_PARTS = {10, 11, *range(30, 39), *range(42, 73)}
MEDIA_PARTS = {12, 21, 22}


class UmpGate:
    def __init__(self, target_id):
        if not re.fullmatch(r'[A-Za-z0-9_-]{11}', target_id):
            raise ValueError('Identifiant vidéo invalide')
        self.target_id = target_id
        self.prefix = bytearray()
        self.payload = bytearray()
        self.kind = None
        self.remaining = 0
        self.mode = None
        self.headers = {}
        self.events = []
        self.decisions = Counter()
        self.parts = Counter()
        self.bytes_in = self.bytes_out = self.bytes_dropped = 0
        self.media_allowed = self.media_blocked = 0
        self.error = None
        self.finished = False
        self.encrypted_chain_broken = False

    def _fail(self, reason):
        if not self.error:
            self.error = reason
            self.events.append({'decision': 'blocked_unknown', 'reason': reason})
        self.bytes_dropped += len(self.prefix) + len(self.payload)
        self.prefix.clear()
        self.payload.clear()
        self.headers.clear()

    def _emit(self, data, output):
        output.extend(data)
        self.bytes_out += len(data)

    def _start(self, output):
        if self.kind == 20:
            if self.remaining > 16384:
                self._fail('En-tête média trop grand ; suite de la réponse bloquée')
            self.mode = 'header'
        elif self.kind in MEDIA_PARTS:
            self.mode = 'id'
        elif self.kind in CONTROL_PARTS:
            self.mode = 'pass'
            self._emit(self.prefix, output)
            self.prefix.clear()
        else:
            self.mode = 'drop'
            self.bytes_dropped += len(self.prefix)
            self.prefix.clear()
            self.events.append({'partType': self.kind, 'decision': 'blocked_unknown',
                                'reason': 'Type de bloc UMP non reconnu'})

    def _finish_part(self, output):
        if self.mode == 'header':
            try:
                header = media_header(self.payload)
            except (ValueError, UnicodeError):
                self._fail('En-tête média illisible ; suite de la réponse bloquée')
                return
            header_id, video_id = header.get('headerId'), header.get('videoId')
            allowed = header_id is not None and video_id == self.target_id
            decision = 'allowed_target' if allowed else 'blocked_other' if video_id else 'blocked_unknown'
            if header_id is not None:
                if header_id not in self.headers and len(self.headers) >= 4096:
                    self._fail('Trop d’en-têtes ; suite de la réponse bloquée')
                    return
                self.headers[header_id] = (allowed, video_id)
            else:
                # Ne pas réutiliser une association antérieure après un en-tête ambigu.
                self.headers.clear()
                decision = 'blocked_unknown'
            self.decisions[decision] += 1
            self.events.append({'decision': decision, 'ump_header': header,
                                'reason': 'Vidéo choisie' if allowed else
                                'Autre vidéo, publicité non confirmée' if video_id else 'Identifiant absent'})
            raw = self.prefix + self.payload
            if allowed:
                self._emit(raw, output)
            else:
                self.bytes_dropped += len(raw)
        elif self.mode == 'id':
            # Bloc média vide ou identifiant tronqué : rien n'a été transmis.
            self.bytes_dropped += len(self.prefix) + len(self.payload)
            self.events.append({'decision': 'blocked_unknown', 'partType': self.kind,
                                'reason': 'Identifiant de bloc absent ou tronqué'})
        self.prefix.clear()
        self.payload.clear()
        self.kind = self.mode = None

    def feed(self, chunk):
        if self.finished:
            raise ValueError('Réponse déjà terminée')
        self.bytes_in += len(chunk)
        if not chunk:
            self.finished = True
            if self.prefix or self.kind is not None:
                self._fail('Réponse UMP tronquée')
            return b''
        if self.error:
            self.bytes_dropped += len(chunk)
            return b''
        output = bytearray()
        view = memoryview(chunk)
        offset = 0
        while offset < len(view):
            if self.kind is None:
                self.prefix.append(view[offset])
                offset += 1
                first = ump_uint(self.prefix)
                second = ump_uint(self.prefix, first[1]) if first else None
                if not second:
                    continue
                self.kind, self.remaining = first[0], second[0]
                self.parts[str(self.kind)] += 1
                self._start(output)
            if self.error:
                self.bytes_dropped += len(view) - offset
                break
            if self.mode == 'id' and self.remaining and offset == len(view):
                break
            if self.mode == 'id' and self.remaining:
                self.payload.append(view[offset])
                offset += 1
                self.remaining -= 1
                parsed = ump_uint(self.payload)
                if parsed:
                    header_id = parsed[0]
                    allowed, video_id = self.headers.get(header_id, (False, None))
                    if self.kind == 12:
                        if self.encrypted_chain_broken:
                            allowed = False
                        if not allowed:
                            self.encrypted_chain_broken = True
                    self.mode = 'pass' if allowed else 'drop'
                    raw = self.prefix + self.payload
                    if allowed:
                        self._emit(raw, output)
                    else:
                        self.bytes_dropped += len(raw)
                    if header_id not in self.headers:
                        self.events.append({'decision': 'blocked_unknown', 'partType': self.kind,
                                            'headerId': header_id, 'reason': 'En-tête associé inconnu'})
                    elif self.kind == 12 and not allowed and video_id == self.target_id:
                        self.events.append({'decision': 'blocked_unknown', 'partType': self.kind,
                                            'headerId': header_id,
                                            'reason': 'Chaîne de chiffrement interrompue par un bloc retiré'})
                    self.prefix.clear()
                    self.payload.clear()
            elif self.mode != 'id':
                take = min(self.remaining, len(view) - offset)
                data = view[offset:offset + take]
                if self.mode == 'header':
                    self.payload.extend(data)
                elif self.mode == 'pass':
                    self._emit(data, output)
                    if self.kind in (12, 21):
                        self.media_allowed += take
                else:
                    self.bytes_dropped += take
                    if self.kind in (12, 21):
                        self.media_blocked += take
                offset += take
                self.remaining -= take
            if not self.remaining:
                self._finish_part(output)
            if self.error:
                self.bytes_dropped += len(view) - offset
                break
        return bytes(output)

    def take_events(self):
        events, self.events = self.events, []
        return events

    def summary(self):
        return {'targetVideoId': self.target_id, 'receivedBytes': self.bytes_in,
                'forwardedBytes': self.bytes_out, 'withheldBytes': self.bytes_dropped,
                'allowedMediaBytes': self.media_allowed, 'blockedMediaBytes': self.media_blocked,
                'decisions': dict(self.decisions), 'parts': dict(self.parts), 'parseError': self.error}
