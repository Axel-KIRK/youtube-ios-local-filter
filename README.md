# YouTube iOS Local Filter

Research and development of a filter for the **official YouTube app on iPhone**. The approach removes advertising instructions sent to the player while allowing media to pass through.

**Project status: a Mac-based proxy prototype worked during a live session. The standalone iOS app is not yet a usable ad blocker.** The product goal is a simple installation, a few confirmations in Settings, and a switch — with no computer or Developer Mode required for the end user.

## October 18, 2026 results

On an **iPhone SE (3rd generation), iOS 18.6.1 (22G90)**, the proxy removed advertising fields from 43 responses covering 41 distinct video identifiers. The user manually switched between many videos and reported no ads during that sequence. Main-video playback progress was also checked.

This result covers one session with a local certificate explicitly trusted on the iPhone. It does not measure how many ads were prevented. A final ambiguous report of a stall remains unresolved and is preserved in the experiment report.

A later test using the **Swift HTTPS proxy and engine** also started videos without ads on the same phone. During the recorded window it rewrote 21 responses and passed 40 successful media responses. The Mac was still required. Three unclassified upstream failures were logged; they are preserved in the [Swift session record](evidence/swift-proxy-session.json), not hidden by the positive user report.

On October 19, the app and embedded Network Extension were successfully signed and installed on that iPhone, and the app launched. The device was provisioned through an activated developer membership. This establishes development installation, not working autonomous filtering; see the [installation record](evidence/native-installation.json).

## Documentation

- [Detailed experiments and final findings](docs/EXPERIMENTS-2026-10-18.md)
- [Reproduce the prototype and undo the setup](docs/REPRODUCE.md)
- [iOS architecture, user setup, and remaining work](docs/IOS-ARCHITECTURE.md)
- [Swift engine, verification app, and build instructions](docs/DEVELOPMENT.md)
- [Swift HTTPS proxy and transport checks](docs/SWIFT-PROXY.md)
- [Native extension setup and device validation](docs/NATIVE-PROTOTYPE.md)
- [Apple signing and App Store assessment](docs/APPLE-DISTRIBUTION.md)
- [Publishable session measurements](evidence/session-summary.json)
- [Python source of the tested prototype](reference/proxy/)

This repository contains no private certificate keys, cookies, authenticated requests, videos, or personal screenshots. Test fixtures are synthetic. Publishing the source does not provide a signed application or an App Store release.

## Initial iOS implementation

The engine has been ported to `Sources/LocalFilterCore`: Protobuf, UMP streams, Onesie 0/25 envelopes, authentication, rewriting, and media preservation. `ios/App` now includes an experimental connection setup, certificate installation guide, start/stop controls, and a synthetic engine check. `ios/Tunnel` connects the HTTPS proxy to a Network Extension, stores its authority in Keychain, and reports aggregate activity. **The app and extension are provisioned and installed on the test iPhone; autonomous filtering remains unverified.** See the [native prototype procedure](docs/NATIVE-PROTOTYPE.md).

`Sources/LocalFilterTransport` now connects that engine to a scoped HTTPS proxy, runnable on a Mac as `local-filter-proxy`. A real iPhone playback session succeeded through this backend, alongside synthetic TLS integration tests; an autonomous on-device test is still outstanding.

October 18 validation: **26 Swift tests (including 9 transport integration tests) and 48 Python tests passed**, regenerated fixtures were identical, and the app and its embedded Network Extension compiled successfully for the iOS simulator. See the [preserved validation record](evidence/native-validation.json) for the tested revision and CI run. No standalone filtering test on an iPhone is claimed yet.

```sh
swift test
```
