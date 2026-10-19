# Developing the iOS app

## Implemented components

`LocalFilterCore` uses CryptoKit, CommonCrypto, and zlib provided by Apple platforms. The package's new transport additionally downloads pinned Apple SwiftNIO, NIOSSL, and Swift Certificates dependencies. The core ports the prototype's processing:

- Bounded Protobuf parsing, preservation of unknown bytes, and removal of fields 7/45/68 from a recognized PlayerResponse.
- `/player` and `/get_watch` API responses.
- Incremental UMP rewriting, Onesie 0 and 25 envelopes, verified HMAC, AES-CTR, bounded gzip, a fresh IV, and a new HMAC.
- Byte-for-byte media forwarding, with the original response returned for unknown formats, truncation, missing keys, or authentication failure.
- An in-memory hotconfig key cache with client isolation, expiration, and a 32-entry limit.
- An HTTP integration boundary with exact host and path checks.

`ResponseProcessor` **does not open connections itself**. `LocalFilterTransport` now supplies decrypted responses, adjusts HTTP framing and stale validation headers, and connects its incremental output to the downstream connection. The new [Swift proxy and its test procedure](SWIFT-PROXY.md) are separate from the preserved Python implementation. An empty intermediate stream output must never be converted into the end of an HTTP response.

Each stream and its cache must be used on the same serial executor. Diagnostics are limited to 64 unconsumed events per response; the consumer retrieves them with `drainEvents()`. Keys are not written to disk. Memory usage in the future networking process still needs measurement on a device.

## Swift tests

On a Mac with full Xcode and a compatible Swift toolchain (the pinned dependencies require at least Swift 6.1; this transport was compiled locally with Swift 6.3.3):

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

The SwiftUI code is in `ios/App`; the experimental provider is in `ios/Tunnel`. The app requests a local connection, guides explicit certificate installation/trust, starts/stops filtering, and displays aggregate activity. The extension uses the Swift HTTPS proxy and its own Keychain authority. It does not silently install a profile or enable trust. Signed installation and app launch succeeded on the test iPhone; routing and filtering still need device validation. See [the native prototype procedure](NATIVE-PROTOTYPE.md).

`LocalFilterSetup` adds an iOS 17/macOS 14 system-trust preflight through an explicitly configured loopback proxy. Two additional integration tests verify rejection of an untrusted certificate and no direct fallback when the proxy is unavailable. All 11 transport/setup tests passed on October 19. The signed app was updated and its missing-certificate activation guard passed on the iPhone: filtering remained off in setup mode. No synthetic trust exception is used by the app. The Debug-only `--verify-local-setup` launch argument exercises this same activation path for device diagnostics.

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

CI runs the Swift tests, builds the simulator app, and separately checks the Python tests and fixture regeneration. The complete CI run passed **26 Swift tests (9 transport integration tests), 48 Python tests, byte-identical regenerated fixtures, and a successful unsigned simulator build of the app and its embedded Network Extension**. The transport tests include public certificate export and navigation cancellation. The tested revision and CI run are preserved in [native-validation.json](../evidence/native-validation.json).

The same app and extension also compiled locally for a generic arm64 iPhone with Xcode 26.6 and the iPhoneOS 26.5 SDK, with signing disabled. See [the local build record](../evidence/local-ios-build.json).

On October 19, the same source revision was built with automatic development signing, installed on the paired iPhone, and launched successfully. Both the app and embedded extension have verified signatures and the packet-tunnel entitlement. See the [signed installation record](../evidence/native-installation.json). Generated projects, provisioning profiles, certificates, private keys, and build logs remain local.

Neither an unsigned device build nor a simulator build demonstrates working network interception on an iPhone. Device installation and TestFlight require signing and the appropriate capabilities on the project's Apple account; no account or provisioning profile is included.

## Next milestone

The Mac Swift HTTPS proxy has passed a real iPhone playback trial. The native app is now provisioned and installed. Validate the extension's routing, its per-installation Keychain storage, and certificate setup. Then reproduce ad-free startup **with the Mac disconnected** and simplify the installation guide. Distribution requirements are distinguished from technical feasibility in the [architecture document](IOS-ARCHITECTURE.md).
