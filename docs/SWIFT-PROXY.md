# Swift HTTPS proxy

## Current scope

`LocalFilterTransport` connects real HTTPS sockets to `LocalFilterCore`. `local-filter-proxy` runs this code on a Mac so transport behavior can be tested before device provisioning is available. It is a **YouTube-only CONNECT backend**, not a complete VPN or a general browsing proxy. Non-target CONNECT requests receive 403. The iOS screen is still a verification preview and does not start this server yet.

The backend accepts `youtubei.googleapis.com`, `youtubei-att.googleapis.com`, and valid `*.googlevideo.com` names on port 443. It resolves a destination off the event loop, rejects local/reserved addresses, and connects to the checked address while validating the original hostname and upstream TLS certificate. It offers HTTP/1.1 downstream and upstream. Other traffic must use a separate forwarding layer or remain outside the routing scope.

One NIO event loop owns connections, the ephemeral Onesie key cache, and the leaf-certificate cache. API responses up to 4 MiB are buffered for processing; larger responses pass through unchanged. Recognized UMP responses stream through the core without buffering media. Request bodies have a 4 MiB limit and receive 413 if exceeded. Slow downstream writes pause upstream reads. Upstream connection establishment and inactivity are bounded. These limits still need measurement against the iPhone extension's memory budget.

The transport removes stale hot-config hash headers when a key is missing, captures returned key configuration, and invalidates only the relevant client's cache when a new wrapped key appears. Changed responses lose stale length/digest/ETag headers; gzip API bodies are decoded with a size limit and sent uncompressed only if rewritten. Unknown bodies retain their original bytes. Empty intermediate fragments never terminate HTTP. This version does not implement HTTP/2, HTTP/3, generic tunneling, WebSockets, or HTTP pipelining.

Diagnostics contain hostnames, a small fixed set of endpoint paths, status codes, and rewrite flags. They omit full URLs, query parameters, request/response payloads, authentication headers, playback IDs, and keys. A rewrite flag is not an ad-prevention counter.

## Run a local test

```sh
swift build --product local-filter-proxy
swift run local-filter-proxy --create-ca local-evidence/my-test-ca
swift run local-filter-proxy \
  --ca-cert local-evidence/my-test-ca/ca.pem \
  --ca-key local-evidence/my-test-ca/ca-key.pem
```

The authority is unique, generated locally, and written with private file permissions. Only the public `ca.pem` should ever be installed on a test device. Nothing installs or trusts it automatically. Existing matching RSA PEM authority/key files from the Python prototype can also be supplied, including mitmproxy's combined key-and-certificate PEM. The proxy never exports the loaded private key.

The default listener is `127.0.0.1:8881`. Explicit `--listen` and `--allow-client` options support a controlled LAN test. Do not configure this scoped backend as the phone's general Wi-Fi proxy: unrelated destinations are deliberately rejected. Use the preserved front proxy with `--https-port 8881` to route only the YouTube inspection scope to it, and keep a rollback path to the original backend. Client identity is the immediate peer IP; a front proxy serving multiple devices would need an authenticated identity mechanism before claiming per-device isolation. `--observe` disables rewriting while retaining inspection of key configuration.

For a Mac-only certificate and transport check:

```sh
curl --proxy http://127.0.0.1:8881 \
  --cacert local-evidence/my-test-ca/ca.pem \
  https://youtubei.googleapis.com/youtubei/v1/player
```

A 405 response is expected for this unauthenticated GET. It checks CONNECT, downstream trust, verified upstream TLS, and HTTP forwarding; it does **not** show ad filtering or video playback.

## Verification and remaining work

The Swift executable compiled locally and successfully forwarded the Google API's 405 response through the original trusted RSA authority on October 18, 2026. This is a transport smoke test, not an iPhone result.

`LocalFilterTransportTests` adds synthetic TLS integration tests using a local HTTPS server and curl: clear/gzip API rewriting, fragmented UMP/media preservation, encrypted Onesie key acquisition over HTTP, malformed and oversized fallback, rejected CONNECT destinations, mismatched authority keys, and untrusted upstream certificates. Test-only upstream address/trust overrides are internal to the module and are not command-line options. See CI for the result on the current revision; the earlier engine-only validation record does not cover this new transport.

Before claiming an autonomous iPhone filter, complete and validate the network extension, device signing, certificate installation/trust, suspension and lock/resume, cancellation, memory/battery use, and fresh multi-video playback sessions. The desktop reference remains available for rollback.
