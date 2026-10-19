# Native iPhone prototype

## What this increment implements

The app embeds a `NEPacketTunnelProvider` extension, which starts the same Swift HTTPS proxy tested through the Mac. The extension creates a P-256 authority unique to its installation and stores its certificate and key in its own Keychain access group, with `AfterFirstUnlockThisDeviceOnly` accessibility and synchronization disabled. The app never receives the private key. Storage errors do not silently generate a replacement authority.

The provider starts with eight maximum client connections. Setup mode serves the public certificate on a loopback HTTP endpoint without applying YouTube proxy settings. Filtering mode adds an HTTPS proxy for `youtubei.googleapis.com`, `youtubei-att.googleapis.com`, and `googlevideo.com` suffixes. There are no default IPv4/IPv6 routes, DNS interception, packet discard loop, remote VPN server, on-demand rules, or private API calls. Unrelated traffic is intended to remain outside this proxy scope.

**This routing strategy is experimental.** Apple's proxy-domain matching is documented for split tunnels, and Apple explicitly lists local proxies as an unsupported packet-tunnel use. It is unknown whether all relevant YouTube connections honor these settings on the target device. HTTP/3 and sockets that bypass system proxies are not captured. A successful VPN connection is not proof of filtering. [Proxy domain matching](https://developer.apple.com/documentation/networkextension/neproxysettings/matchdomains), [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)

The interface distinguishes setup, waiting for traffic, and received responses. Counters represent completed/rewritten responses, not prevented ads. Status messages contain only aggregates and the local public-certificate URL. No request URLs, cookies, video IDs, or payloads are persisted. A three-second status timeout prevents an unavailable provider from leaving the app waiting indefinitely.

The app now verifies certificate trust and connectivity before applying filtering settings. It starts in setup mode, then makes an unauthenticated HEAD request to the YouTube player API through an explicit loopback HTTP CONNECT proxy using the device's normal TLS trust. The ephemeral session has no cookies, credential store, cache, redirects, custom trust anchors, or direct-connection fallback. Missing trust or an unavailable connection leaves the provider in setup mode without redirecting YouTube. Successful checks are repeated immediately before enabling filtering, and restarting in filter mode resets probe counters. Returning from Settings also triggers a setup check. A manual checkbox is no longer accepted as evidence of trust.

## Development installation

1. Generate the project with `xcodegen generate --spec ios/project.yml` and open `ios/LocalFilter.xcodeproj` in compatible Xcode.
2. Select an activated developer team for **both** LocalFilter and LocalFilterTunnel. Automatic signing must provision their Network Extension capability. Keep team IDs, profiles, and account details out of source control. A pending enrollment or unsigned simulator build does not establish this capability.
3. Build and run on the paired test iPhone. Developer Mode is a development-installation requirement, not the intended end-user distribution flow.
4. **For an autonomous test, first turn off the old manual Wi-Fi proxy.** Record its previous setting for rollback. Otherwise the Mac can produce a misleading success.
5. In LocalFilter, choose **Prepare connection** and approve the iOS VPN-configuration prompt. This starts setup mode; it does not redirect YouTube yet.
6. Choose **Open certificate in Safari**. Install LocalFilter Personal CA through Settings → General → VPN & Device Management, then enable full trust in Settings → General → About → Certificate Trust Settings. This is a new device-local authority; the older Mac PoC certificate does not replace it.
7. Return to LocalFilter. It checks the real certificate and connection automatically. Choose **Verify and enable filtering**; filtering starts only after another successful check. If verification fails, complete the indicated setup step or retry when the network is available. The provider remains in setup mode, so YouTube is not redirected.
8. Reopen the official YouTube app and choose several fresh videos. Confirm that the app receives traffic and reports rewriting. Compare actual playback with the displayed counts.

The app and embedded extension compiled successfully for the iOS simulator in [CI](https://github.com/Axel-KIRK/youtube-ios-local-filter/actions/runs/39145003403). A [local unsigned arm64 iPhone build](../evidence/local-ios-build.json) also succeeded after installing the iOS platform in Xcode 26.6.

On October 19, an activated membership provisioned both targets for the test iPhone SE (3rd generation), iOS 18.6.1. A signed Debug build succeeded; both signatures and their `packet-tunnel-provider` entitlements were verified. Installation and app launch succeeded through `devicectl`. The user confirmed that the old manual Wi-Fi proxy was disabled and that preparing the connection reached **Ready for certificate setup**. This state requires a connected provider and a decoded setup-status response. **These results establish installation and setup-mode startup, not successful local proxy routing or ad removal.** Certificate trust and live filtering are separate checks; see the [installation record](../evidence/native-installation.json).

The user subsequently confirmed downloading and installing the new device-local certificate and enabling full trust in Settings. This is a user report; the app's trust toggle is not independent validation of iOS trust. Both app and extension processes were observed running during setup.

**The first filtering trial failed:** YouTube did not load, and LocalFilter displayed **Waiting for YouTube traffic**. This state means zero completed responses, not necessarily zero incoming connections. The app, extension, and YouTube processes were still present; no crash was established. Additional aggregate diagnostics now separate accepted sockets, CONNECT requests, decrypted requests, downstream errors, upstream errors, and policy/capacity rejections. Fixed error categories and aggregate counts can be inspected in the app and the extension's system log; URLs, credentials, payloads, and raw error descriptions are not added to those logs. The cause and a working autonomous session remain unverified.

The diagnostic build passed all nine transport integration tests and was signed, installed, and launched. One observed snapshot showed 15 accepted connections and CONNECT requests, 15 downstream TLS failures, zero decrypted requests, zero completed responses, zero upstream failures, and zero policy/capacity rejections. A debugger inspection identified EOF during the handshake for `youtubei.googleapis.com`. Stopping the local connection restored YouTube, as confirmed by the user.

A separate Mac `curl` request through a temporary USB forward to the **iPhone's** proxy successfully validated its exported public CA and received the expected HTTP 405 from a GET to `/youtubei/v1/player`. This checks the proxy and its upstream path, not iOS certificate trust or YouTube playback. It adds one completed response to that diagnostic session; counters must be reset before evaluating a fresh playback trial. The USB forward was stopped after the check.

**Correction to the initial certificate report:** the device's profile inventory listed only the older Mac PoC certificate, and the user confirmed the same in Settings. The new LocalFilter CA was not installed. Its installation remains the next step; the missing trust is a likely cause of the downstream TLS failure, but a successful retest is required before claiming resolution.

The subsequent setup correction passed 11 transport/setup tests, including rejection of an untrusted authority and refusal to fall back to a direct connection when the proxy is unavailable. A signed build was installed on the same phone. A Debug-only `--verify-local-setup` launch option exercised the normal activation path without UI taps: the device reported `certificate_not_trusted`, remained in `mode=setup`, and did not enable filtering. This validates the missing-certificate guard on the phone; it is not a successful playback test.

## What setup can automate

The app creates and retains its authority, serves the public certificate, verifies the actual connection, and controls filtering. On an ordinary personally managed iPhone, downloading a profile still requires installation in Settings and separate root-certificate trust approval. Apple documents automatic deployment through device management or Apple Configurator, which is a different installation model and is not added by this app. Downloaded profiles also expire if they are not installed within eight minutes; the app can serve the same public certificate again without replacing its key. [Profile installation](https://support.apple.com/en-us/102400), [Certificate trust](https://support.apple.com/en-us/102390).

## Required device checks

- Disconnect the Mac and repeat startup and multiple-video playback, including a video known to show ads. Record the YouTube version and both failures and successes.
- Verify Safari, other apps, Wi-Fi/cellular changes, lock/resume, and background operation. Absence of a default tunnel route does not by itself prove correct system routing.
- Verify the expected error when certificate trust is absent, then successful TLS after trust is enabled. Verify that setup mode leaves YouTube usable before trust.
- Confirm that restarting the extension preserves its authority and that a locked/unavailable Keychain does not replace it.
- Measure peak extension memory and battery use under parallel video/prefetch traffic. Eight connections and bounded bodies are limits, not a demonstrated memory-budget guarantee.
- Check cancellation, media progress, mid-roll behavior, and unknown-key/schema fallback. Upstream TLS verification must remain enabled.
- Check Stop, failed starts, configuration removal, and recovery without a Mac. Do not proceed to public distribution until these checks and the separate App Store assessment are complete.

## Stop and remove

Use **Stop local connection** to stop the provider and release its in-memory keys. Then **Remove local connection** removes the saved VPN configuration. Remove the certificate separately in Settings → General → VPN & Device Management. Deleting the app does not reliably remove an installed profile or a Keychain item. Certificate renewal/reset and migration are still outstanding before release; an expired or corrupt stored authority currently fails startup instead of replacing trust silently.

For rollback to the desktop experiment, stop the native connection and restore the previously recorded Wi-Fi proxy. Never report such a fallback as autonomous filtering.
