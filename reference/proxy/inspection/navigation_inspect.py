"""Bounded inspection of the navigation IDs and flags relevant to filtering.

Public david zeng/innertube schemas: GetWatchRequest.player_request=2,
watch_next_request=3; WatchNextRequest.video_id=2, is_ad_playback=9,
watch_next_type=14, is_embed_preview=42. A PlayerRequest alone does not
prove selection: it may request an advertisement or preload."""
import json
import re

try:
    from .api_inspect import wire_fields
except ImportError:
    from api_inspect import wire_fields


def one(fields, number, kind):
    found = [(k, v) for n, k, v in fields if n == number]
    if not found:
        return None
    if len(found) != 1 or found[0][0] != kind:
        raise ValueError('Ambiguous field')
    return found[0][1]


def video_id(value):
    if isinstance(value, bytes):
        value = value.decode('ascii')
    return value if isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_-]{11}', value) else None


def inspect_navigation(body, path):
    if not body or len(body) > 1024 * 1024 or path not in ('/youtubei/v1/next', '/youtubei/v1/get_watch', '/youtubei/v1/player'):
        return None
    try:
        if body.lstrip().startswith(b'{'):
            root = json.loads(body)
            source = root.get('watchNextRequest') if path.endswith('/get_watch') else root
            if not isinstance(source, dict):
                return None
            result = {'videoId': video_id(source.get('videoId')), 'isAdPlayback': source.get('isAdPlayback', False),
                      'watchNextType': source.get('watchNextType'), 'isEmbedPreview': source.get('isEmbedPreview', False),
                      'hasContinuation': bool(source.get('continuation')), 'schema': 'json'}
        else:
            fields = wire_fields(body)
            if path.endswith('/get_watch'):
                nested = one(fields, 3, 2)
                if nested is None:
                    return {'schema': 'protobuf-get-watch-without-navigation', 'eligible': False}
                fields = wire_fields(nested)
            result = {'videoId': video_id(one(fields, 2, 2)),
                      'isAdPlayback': one(fields, 9, 0) if not path.endswith('/player') else None,
                      'watchNextType': one(fields, 14, 0) if not path.endswith('/player') else None,
                      'isEmbedPreview': one(fields, 42, 0) if not path.endswith('/player') else None,
                      'hasContinuation': bool(one(fields, 8, 2)) if not path.endswith('/player') else False,
                      'schema': 'protobuf'}
        result['source'] = path.rsplit('/', 1)[-1]
        result['eligible'] = bool(result.get('videoId') and result['source'] != 'player'
                                  and result['isAdPlayback'] in (None, False, 0)
                                  and result['isEmbedPreview'] in (None, False, 0)
                                  and not result['hasContinuation']
                                  and result['watchNextType'] in (None, 1, 'WATCH_WHILE'))
        return result
    except (ValueError, UnicodeError, TypeError, AttributeError, RecursionError):
        return {'schema': 'unrecognized', 'eligible': False}
