"""Résumé local de réponses YouTube. Aucun script tiers ni modification de réponse."""
import json
import re
from collections import Counter
from urllib.parse import urlsplit


def wire_fields(data):
    offset = 0
    result = []

    def varint():
        nonlocal offset
        value = 0
        for shift in range(0, 70, 7):
            if offset >= len(data):
                raise ValueError("varint tronqué")
            byte = data[offset]; offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value
        raise ValueError("varint trop long")

    while offset < len(data):
        tag = varint(); number, kind = tag >> 3, tag & 7
        if not 0 < number < 2**29:
            raise ValueError("numéro de champ invalide")
        if kind == 0:
            value = varint()
        elif kind in (1, 2, 5):
            size = varint() if kind == 2 else 8 if kind == 1 else 4
            if offset + size > len(data):
                raise ValueError("champ tronqué")
            value = data[offset:offset + size]; offset += size
        else:
            raise ValueError("type de champ non pris en charge")
        result.append((number, kind, value))
        if len(result) > 100000:
            raise ValueError("trop de champs")
    return result


def inspect_body(body, path):
    summary = {"adPlacements": 0, "adSlots": 0, "playerAds": 0, "playerMessages": 0,
               "schema": "unknown", "mediaPaths": []}
    try:
        if body.lstrip().startswith((b"{", b"[")):
            obj = json.loads(body)
            stack = [obj]
            while stack:
                current = stack.pop()
                if isinstance(current, dict):
                    for key, value in current.items():
                        if key in ("adPlacements", "adSlots", "playerAds"):
                            summary[key] += len(value) if isinstance(value, list) else int(bool(value))
                        if key == "videoDetails" and isinstance(value, dict):
                            summary["videoId"] = str(value.get("videoId", ""))[:32]
                            summary["title"] = str(value.get("title", ""))[:300]
                        if isinstance(value, (dict, list)):
                            stack.append(value)
                elif isinstance(current, list):
                    stack.extend(v for v in current if isinstance(v, (dict, list)))
            summary["schema"] = "json"
        else:
            fields = wire_fields(body)
            summary["topFields"] = dict(Counter(str(number) for number, _, _ in fields))
            players = []
            if path.endswith("/player"):
                players = [fields]
            elif path.endswith("/get_watch"):
                for number, kind, value in fields:
                    # Watch.contents=1 ; OnesieInnertubeResponse.contents=4
                    # concerne une autre enveloppe, pas /get_watch.
                    if number == 1 and kind == 2:
                        for sub, subkind, subvalue in wire_fields(value):
                            if sub == 2 and subkind == 2:
                                players.append(wire_fields(subvalue))
            summary["schema"] = "protobuf-player-candidate" if players else "protobuf-unmapped"
            for player in players:
                # PlayerResponse : 7=player_ads, 45=ad_placements, 68=ad_slots.
                # Comptage de champs, pas de publicités effectivement affichées.
                summary["playerMessages"] += 1
                summary["playerAds"] += sum(n == 7 and k == 2 for n, k, _ in player)
                summary["adPlacements"] += sum(n == 45 and k == 2 for n, k, _ in player)
                summary["adSlots"] += sum(n == 68 and k == 2 for n, k, _ in player)
                for n, k, value in player:
                    if n == 11 and k == 2:
                        for sub, subkind, text in wire_fields(value):
                            if subkind == 2 and sub in (1, 15):
                                decoded = text.decode('utf8')
                                if sub == 1 and re.fullmatch(r'[A-Za-z0-9_-]{11}', decoded):
                                    summary['videoId'] = decoded
                                elif sub == 15:
                                    summary['title'] = decoded[:300]
    except (ValueError, UnicodeDecodeError, RecursionError):
        summary["schema"] = "unparsed"
        summary["parseError"] = "Format non reconnu ; réponse transmise inchangée"
    # Ne publier ni signature, ni jeton, ni paramètre de requête dans le journal.
    for match in re.finditer(rb'https://[a-zA-Z0-9.-]+\.googlevideo\.com/[a-zA-Z0-9_/-]+', body):
        url = urlsplit(match.group().decode('ascii'))
        # Les URL de manifestes placent parfois signature/IP dans le chemin.
        path = next((prefix for prefix in ('/videoplayback', '/initplayback',
                    '/api/manifest/hls_variant', '/api/manifest/hls_playlist', '/api/manifest/dash')
                     if url.path == prefix or url.path.startswith(prefix + '/')), '/[chemin masqué]')
        value = 'https://' + url.netloc + path
        if value not in summary["mediaPaths"]:
            summary["mediaPaths"].append(value)
        if len(summary["mediaPaths"]) >= 30:
            break
    return summary
