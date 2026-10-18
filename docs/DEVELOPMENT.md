# Developing the iOS app

## Implemented components

`LocalFilterCore` is a Swift package with no downloaded dependencies. It uses CryptoKit, CommonCrypto, and zlib provided by Apple platforms. It ports the prototype's processing:

- Bounded Protobuf parsing, preservation of unknown bytes, and removal of fields 7/45/68 from a recognized PlayerResponse.
- `/player` and `/get_watch` API responses.
- Incremental UMP rewriting, Onesie 0 and 25 envelopes, verified HMAC, AES-CTR, bounded gzip, a fresh IV, and a new HMAC.
- Byte-for-byte media forwarding, with the original response returned for unknown formats, truncation, missing keys, or authentication failure.
- An in-memory hotconfig key cache with client isolation, expiration, and a 32-entry limit.
- An HTTP integration boundary with exact host and path checks.

`ResponseProcessor` **does not open connections**. A future transport must supply responses already decrypted by the MITM, apply the necessary header changes, remove `x-youtube-hot-hash-data` when `needsFreshConfiguration` requests it, and handle cancellation and backpressure. An empty intermediate stream output must never be converted into the end of an HTTP response.

Each stream and its cache must be used on the same serial executor. Diagnostics are limited to 64 unconsumed events per response; the consumer retrieves them with `drainEvents()`. Keys are not written to disk. Memory usage in the future networking process still needs measurement on a device.

## Swift tests

On a Mac with full Xcode and Swift 6 installed (XCTest is not included in every Command Line Tools-only installation):

```sh
swift test
```

With only Command Line Tools, the engine can also be compiled and its synthetic diagnostic run without XCTest:

```sh
swift run local-filter-check
```

The Python engine generates `Tests/LocalFilterCoreTests/Fixtures/onesie.json` from synthetic data. These fixtures check the port against both envelopes, with and without gzip, without publishing user traffic. Their `00 01 … 1f` key is a public test constant. To regenerate them in the prototype environment:

```sh
.venv-https/bin/python scripts/generate-fixtures.py
```

## iOS project

The SwiftUI code is in `ios/App`. It presents a readable setup outline and a local engine check. It explicitly displays an inactive filter: **no local proxy, VPN extension, or certificate authority is connected in this version**. It installs no profile and changes no trust setting.

With full Xcode and XcodeGen installed:

```sh
xcodegen generate --spec ios/project.yml
open ios/LocalFilter.xcodeproj
```

To build an unsigned simulator app:

```sh
xcodebuild -project ios/LocalFilter.xcodeproj -scheme LocalFilter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

CI runs the Swift tests, builds the simulator app, and separately checks the Python tests and fixture regeneration. The initial complete run passed: **16 Swift tests, 48 Python tests, byte-identical regenerated fixtures, and a successful simulator build**. The tested revision and CI run are preserved in [native-validation.json](../evidence/native-validation.json).

A simulator build does not demonstrate working network interception on an iPhone. Device installation and TestFlight require signing and the appropriate capabilities on the project's Apple account; no account or provisioning profile is included.

## Next milestone

Implement and measure the local HTTPS proxy while YouTube is in the foreground, connect the engine, and create a private certificate authority for each installation. Then reproduce ad-free startup **with the Mac disconnected** and simplify the installation guide. Distribution requirements are distinguished from technical feasibility in the [architecture document](IOS-ARCHITECTURE.md).
