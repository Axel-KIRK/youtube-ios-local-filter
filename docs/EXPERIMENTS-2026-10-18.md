# YouTube iOS experiments on October 18, 2026

## Finding to preserve

The method that produced a positive result was **removing advertising instructions from player startup responses** before delivering them to the YouTube app. Blocking the actual advertising video bytes, even with the correct identifier, left the player waiting and was disabled.

The result was obtained in the official app on an **iPhone SE (3rd generation, iPhone14,6), iOS 18.6.1, build 22G90**. The exact YouTube version was not recorded. The connection used a Wi-Fi proxy on a Mac and a local certificate authority installed and explicitly trusted on the phone. YouTube was not replaced and no jailbreak was used.

Between **15:07:35 and 15:13:24 UTC** (17:07:35–17:13:24 in Paris), the logs show **43 modified responses, 41 distinct identifiers, 93 `playerAds` occurrences and 42 `adSlots` occurrences removed**. The user confirmed manually switching videos and seeing no ads during that sequence. An accessibility capture confirmed the main video at 40 seconds of 4 minutes 19 seconds. Later screenshots showed progress, although not all included the playback-position control.

The 41 identifiers include content processed by the network: this does not prove that 41 complete videos were watched. Field counters are not counts of ads prevented. Historical blocking of three domain families was still enabled: ad-program removal was not isolated through a controlled A/B experiment, although domain blocking alone had already failed.

After this sequence, the user reported that it was “stuck on the ads” (translated from French). This could mean a frozen player or a statement about filtering only ads. The subsequent inspection showed a main video and successful downloads; a clarification request was not answered before the documentation request. **This final report remains unresolved.** The project must not be presented as reliable on every startup.

## Environment and final settings

| Component | Value or role |
| --- | --- |
| Tested application | Official YouTube app on iOS; not Safari |
| Entry proxy | Python, TCP 8877 on the Mac's Wi-Fi address, explicitly authorized clients |
| HTTPS relay | mitmproxy 12.2.3, Python 3.13.15, `127.0.0.1:8880` |
| Dashboard | Python, `http://127.0.0.1:8878` |
| Proxy/dashboard Python | 3.14.7 during the session; standard library |
| USB diagnostics | pymobiledevice3 11.35.0, separate Python environment |
| `mode.txt` | `block`: the three historical advertising-domain families |
| `inspection/https-mode.txt` | `observe-media`: targeted APIs and `googlevideo.com` decrypted locally |
| `inspection/ad-program-mode.txt` | `remove`: ad-program removal enabled |
| `inspection/video-filter.json` | `enabled: false`; the old automatic selection/45-second window has no effect on media |
| USB and Developer Mode | Used to observe the screen; not required for the proxy to work |

HTTPS mode and removal mode are independent: `observe-media` does not imply unchanged forwarding when `ad-program-mode` is `remove`.

## Experiment timeline

All times below are **UTC on October 18, 2026**. Add two hours for Paris local time on that date.

| Time | Experiment and observation | Conclusion |
| --- | --- | --- |
| Around 12:24 | Mac-side proxy checks: local page OK, YouTube CONNECT OK with TLS verified, ad domain rejected, private destination rejected. | Transport and access controls validated on the Mac only. |
| 12:26:30, then 12:27 | The iPhone confirms `http://poc.test`. YouTube/API/googlevideo traffic is observed. | Phone traffic crosses the proxy in this experiment. |
| Initial baseline | Two ads on the first video, several videos without ads, then two more ads. Exact number of plays not recorded. | Ad delivery is intermittent; a single ad-free video proves nothing by itself. |
| 12:31:43 | Blocking enabled for `doubleclick.net`, `googleadservices.com`, `googlesyndication.com`, and their subdomains. Previous tunnels closed. | The domain list is actually enforced. |
| 12:34:52 | An ad is visible despite 20 rejected ad-domain connections and 39 allowed tunnels in the phase. The user later reports “3/3”, after returning to observation. | Domain-only blocking fails; all three ads cannot be assigned to one phase. |
| 12:39:23–12:40:01 | Ad 1/2 paused; blocking re-enabled; ad 2/2 continues. Eleven rejections and seven allowed tunnels, including three googlevideo tunnels. | Second failure; earlier prefetching remains possible. |
| Through 13:21 | Dashboard, Clear button, then per-row “Ad?” checkboxes. Addition of IPs, byte counters, durations, and tunnel-closure events. | Correlation tools, not automatic ad classification. |
| Around 13:31–13:45 | Native inspection after the user enables Developer Mode and USB access. Ad sequences and the transition to main content observed. | The screen can be inspected; no usable web DOM was exposed by the app here. |
| Around 13:50 | Public blocking/rewriting projects reviewed. No external script installed on the iPhone and no third-party worker used. | Investigate player responses instead of media-server names. |
| 14:03 | Targeted HTTPS setup and local certificate prepared. YouTube initially fails to load; Safari also shows a TLS warning. | The installed certificate did not yet have full trust. |
| 14:12:57 | After actually enabling trust: API HTTP 200, readable UMP `/videoplayback`, and working playback. | No evidence of certificate pinning blocking this case; the initial problem was iOS trust. |
| 14:19–14:22 | `videoId` extracted from UMP headers and matched to title and screen. At 14:21:12, main-video media downloads while ad 2/2 has 13 seconds left; the main video starts around 14:21:26. | Downloaded does not mean displayed; size, order, and timing alone are insufficient. |
| 14:34:44 | Fixed-ID media filter enabled. An incorrect target is later corrected. | Other content can be withheld, but the player remains stuck on the blocked ad. |
| Around 14:40 | Four creative identifiers found structurally under `PlayerResponse.ad_slots`. | Main content and scheduled creatives can be distinguished without classifying the CDN. |
| 14:43:51 | Streaming bug fixed: return `[]`, not an intermediate `b''` chunk, when there are no bytes to send. | Prevents premature HTTP/1 chunked termination. Main playback resumes, without proving a scheduled ad was skipped. |
| 14:51–14:54 | Automatic video selection from Onesie navigation; 45-second window. Correct target detected at 14:53:03; screen at 14:53:13 stuck on ad 1/2 with less than a second left. | Automatic detection validated, but media blocking remains unsuitable. |
| Around 14:59 | Media filter disabled; ad-instruction removal prepared. | Stop withholding media. |
| Around 15:05 | First removal attempt: real envelope unrecognized, original forwarded, ad visible. | Onesie type 25 stores IV/HMAC differently from type 0. |
| 15:07:09 | First prefetched response successfully decoded and rewritten. | Type 25 envelope fix works on real traffic. |
| 15:07:35 | New selection; three `playerAds` fields removed; main video observed at 40 seconds at 15:08:16. | First documented positive startup. Three fields do not mean three ads prevented. |
| Through 15:13:24 | Forty-three responses modified, 41 identifiers; user reports many manual changes and zero ads. No new `/next` marked `isAdPlayback` in the checked window. | Experimental session success, requiring reproduction under other conditions. |
| Afterwards | Final ambiguous stall report; inspection shows main content playing. | Clarification and repetition needed before concluding either regression or general stability. |

### What the initial counters measured

At 12:32:24, eight tunnels to advertising families had been seen from the iPhone, all during observation: three `ad.doubleclick.net`, then one each for `googleads.g.doubleclick.net`, `tpc.googlesyndication.com`, `ade.googlesyndication.com`, `pagead2.googlesyndication.com`, and `www.googleadservices.com`. There were also 107 googlevideo tunnels. This counts TLS connections, not ads or all HTTP requests inside them.

The 20 rejections during the first failure were three `ad.doubleclick.net`, six `googleads.g.doubleclick.net`, three `tpc.googlesyndication.com`, three `pagead2.googlesyndication.com`, and five `ade.googlesyndication.com`. Retries can increase these numbers without another ad.

The suspected hosts `rr5---sn-u125g5-5w.googlevideo.com` and `rr1---sn-2o25g5-52.googlevideo.com` did not provide reliable rules: these servers can carry different kinds of content. Bytes already cached are not removed by later blocking.

### Manual labels and captures

The initial global “An ad is on screen” checkbox stayed selected for about nine minutes, preventing reliable attribution. Per-connection checkboxes were then used to preserve the user's hypotheses. They do not block the selected row. Clear hides history in the interface; it deletes neither logs nor annotations.

Native access enabled screenshots, accessibility enumeration, and relaunching YouTube. The accessibility press commands sent did not activate Play. The HID touch-control attempt returned error 9021 with an iOS-version requirement from that service. This does not mean all iOS automation requires that version. Keeping the screen awake did not enable those taps. The user therefore continued selecting videos.

## Why media blocking caused stalls

The abandoned strategy associated each UMP block with a `MEDIA_HEADER`, then allowed only the selected identifier. It could withhold an advertising creative, but left intact the instructions telling the player to play it. The screen consequently remained in its advertising state.

The automatic 45-second window fixed manual target selection, not that wait. It was evaluated when a response started: expiration allowed new responses without guaranteeing immediate release of an already-filtered response or the player state.

The idea of an ad-finished event or a Skip tap led to investigation of playback instructions. The implemented solution **does not fabricate an ad-completion event, a tap, or a view event**: it removes the programming before the player interprets it.

## Final mechanism

```text
Official YouTube app on iPhone
    → authorized Wi-Fi proxy on Mac (8877)
    → local HTTPS MITM (8880, YouTube APIs + googlevideo only)
    → server response
    → decode player instructions
    → selectively remove advertising fields
    → re-authenticate and re-encrypt the response for the iPhone
    → stream media unchanged
```

`inspection/ad_program.py` recognizes a `PlayerResponse` using `videoDetails` (field 11, ID in field 1) and the presence of playback field 2 or 4. It only removes length-delimited Protobuf occurrences of these fields:

| Field | Name | Action |
| --- | --- | --- |
| 7 | `playerAds` | Remove associated instructions |
| 45 | `adPlacements` | Same treatment; supported but not counted in the positive sequence |
| 68 | `adSlots` | Remove advertising slots |

Unknown fields retain their original serialized bytes. `/player` can contain the response directly; `/get_watch` uses repeated field 1 containing a `GetWatchResponse`, then its field 2. The final rewriter handles Protobuf, not JSON variants.

### UMP and Onesie

UMP separates control data from media. Its integer encoding differs from Protobuf varints: confusing them produces incorrect decoding. Control parts 10 and 11 are paired; other parts, including media, pass through unchanged.

- **Onesie type 0**: cryptographic parameters are in header field 4. Within those parameters, HMAC is field 4, IV field 5, and compression field 6. The decoded body is a success envelope (`1 = 1`, `2 = 200`) whose field 4 contains the PlayerResponse.
- **Onesie type 25, confirmed on live traffic during this experiment**: UMP part 11 contains `EncryptedInnertubeResponsePart`. Its fields 1, 2, 3, and 4 contain ciphertext, HMAC, IV, and compression respectively. After decryption, repeated field 4 contains GetWatchResponse messages; their field 2 is the PlayerResponse. Looking only in the header for these parameters was the defect in the initial attempt.

The code verifies HMAC-SHA256 over `ciphertext || IV`, decrypts with AES-128-CTR using the first 16 bytes of a 32-byte key, and uses the remaining 16 bytes for the HMAC. It decompresses gzip when requested, rewrites, recompresses, generates a fresh 16-byte IV, and recalculates the HMAC. It does not decrypt video DRM.

Onesie keys come from the API's hotconfig response: path `1 → 16 → 7` (or base64-encoded field 3), then `138536474 → 146311580`. The key is field 1, wrapped key field 2, and TTL field 3. Matching uses the wrapped key's SHA-256 digest and the client. The cache stays in memory, limited to 32 entries and at most one hour. When no key is available, the `/log_event` cache header `x-youtube-hot-hash-data` is removed to allow a fresh configuration to be fetched.

An unknown, oversized, truncated, unauthenticated, or keyless response is forwarded unchanged. The control-block limit is 4 MiB, including decompression. **This fallback prioritizes playback and may allow an ad through.** Memory usage and streaming must be re-evaluated for the iOS port.

### Advertising identifiers

Four creatives were identified under `PlayerResponse.ad_slots`, with durations of **6, 15, 144, and 344 seconds**. Their presence in that structure establishes that they belong to the received advertising program, not that they were all downloaded or displayed. A 344-second ad also disproves the assumption that an ad is always shorter than the main video.

The observed path to their VideoDetails was `68 → 424701016 → 2 → 1 → 500272857 → 2 → 500604390 → 1[index 0 or 1] → 500272857 → 2 → 61554017 → 1 → 11`. Within VideoDetails, fields 1, 15, 16, and 33 gave the ID, title, duration, and author. This is an observation of a private schema that may change, not a contractual API.

## Verification and performance

**48 automated tests passed** on the final prototype. They cover fragmented UMP, memory limits, identifier mapping, the automatic window, Onesie authentication, both envelopes, preservation of media and unknown fields, truncated inputs, and dashboard controls. After timing measurements were added, the 14 removal and HTTP-integration tests were rerun. The dashboard JavaScript also passed `node --check`.

The empty-chunk fix is essential: a mitmproxy streaming callback with no output yet returns `[]`. Returning `b''` in the middle of an HTTP/1 chunked response could be interpreted as its end.

In the ten preserved final samples, rewriting takes approximately **1.8–2.3 ms**, waiting for the control block **4–50 ms**, and the interval from the request to the useful response **0.42–1.31 s**. The latter includes network and server time; it is not the filter's processing cost. The small initial delay perceived by the user was not conclusively attributed. Cancellations and some API errors occurred during rapid video changes without a measured causal link.

## Remaining checks

- Clarify and reproduce the final stall report, with its time, screenshot, and corresponding response.
- Repeat observation/removal/observation under comparable conditions; separately disable domain blocking to isolate effects.
- Test cold starts, key renewal, relay shutdown/restart, long videos, and mid-roll ads.
- Test Shorts, live streams, account changes, another YouTube version, and a second iPhone; none is established yet.
- Measure battery, memory, latency, and stability in a standalone app.
- Validate an iOS network path deployable on a personal phone, then a TestFlight/App Store installation accessible to nontechnical users.

## Evidence preservation

[session-summary.json](../evidence/session-summary.json) contains publishable counts, timestamps, configuration, and timing samples. [source-manifest.json](../evidence/source-manifest.json) links original session sources to their public copies through SHA-256. Test addresses were replaced, the dashboard phone address was made configurable, and user-facing text and comments were translated into English. Hashes identify the resulting public source separately from the original.

Raw evidence remains in the local prototype directory: `events.jsonl`, `inspection/https-events.jsonl`, `ad-identification-proof.json`, `ump-prefetch-proof.json`, `video-filter-verification.json`, `ad-program-verification.json`, native captures, and `latest-tests.txt`. These are not included on GitHub: API responses may contain signed URLs or account information. TLS authority keys also remain private. The old files `LISEZMOI.txt` and `VERIFICATION.txt` are chronological archives; their earliest instructions no longer describe the final state.

## Technical references

- [YouTube-X player hooks](https://github.com/PoomSmart/YouTube-X/blob/main/Tweak.x): the advertising-field-removal approach; this tweak was not injected into our app.
- [Maasea response rewriting](https://github.com/Maasea/sgmodule/blob/master/Script/Youtube/youtube.response.js) and [request rewriting](https://github.com/Maasea/sgmodule/blob/master/Script/Youtube/youtube.request.js): structures and cryptography studied; no Maasea worker used.
- [UMP](https://github.com/davidzeng0/innertube/blob/main/googlevideo/ump.md), [initplayback](https://github.com/davidzeng0/innertube/blob/main/googlevideo/initplayback.md), [EncryptedInnertubeResponsePart](https://github.com/davidzeng0/innertube/blob/main/protos/video_streaming/encrypted_innertube_response_part.proto), [PlayerResponse](https://github.com/davidzeng0/innertube/blob/main/protos/youtube/api/innertube/player_response.proto).
- [MediaHeader](https://github.com/LuanRT/googlevideo/blob/main/protos/video_streaming/media_header.proto) and [Onesie example](https://github.com/LuanRT/googlevideo/tree/main/examples/onesie-request).
- [mitmproxy streaming](https://docs.mitmproxy.org/stable/addons/examples/#example-http-stream-modify-py).
