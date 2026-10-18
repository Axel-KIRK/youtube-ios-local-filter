# YouTube iOS Local Filter

Research and development of a filter for the **official YouTube app on iPhone**. The approach removes advertising instructions sent to the player while allowing media to pass through.

**Project status: a Mac-based proxy prototype worked during a live session. The standalone iOS app is not yet a usable ad blocker.** The product goal is a simple installation, a few confirmations in Settings, and a switch — with no computer or Developer Mode required for the end user.

## October 18, 2026 results

On an **iPhone SE (3rd generation), iOS 18.6.1 (22G90)**, the proxy removed advertising fields from 43 responses covering 41 distinct video identifiers. The user manually switched between many videos and reported no ads during that sequence. Main-video playback progress was also checked.

This result covers one session with a local certificate explicitly trusted on the iPhone. It does not measure how many ads were prevented. A final ambiguous report of a stall remains unresolved and is preserved in the experiment report.

## Documentation

- [Detailed experiments and final findings](docs/EXPERIMENTS-2026-10-18.md)
- [Reproduce the prototype and undo the setup](docs/REPRODUCE.md)
- [iOS architecture, user setup, and remaining work](docs/IOS-ARCHITECTURE.md)
- [Swift engine, verification app, and build instructions](docs/DEVELOPMENT.md)
- [Publishable session measurements](evidence/session-summary.json)
- [Python source of the tested prototype](reference/proxy/)

This repository contains no private certificate keys, cookies, authenticated requests, videos, or personal screenshots. Test fixtures are synthetic. Publishing the source does not provide a signed application or an App Store release.

## Initial iOS implementation

The engine has been ported to `Sources/LocalFilterCore`: Protobuf, UMP streams, Onesie 0/25 envelopes, authentication, rewriting, and media preservation. `ios/App` contains an initial SwiftUI interface that checks this processing with synthetic data. Connecting it to live YouTube traffic and implementing certificate setup remain outstanding. The interface therefore shows **Filter inactive**.

October 18 validation: **16 Swift tests and 48 Python tests passed**, regenerated fixtures were identical, and the app compiled successfully for the iOS simulator. See the [preserved validation record](evidence/native-validation.json) for the tested revision and CI run. No standalone filtering test on an iPhone is claimed yet.

```sh
swift test
```
