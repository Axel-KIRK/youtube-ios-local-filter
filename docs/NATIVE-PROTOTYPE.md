# Native iPhone prototype

## What this increment implements

The app embeds a `NEPacketTunnelProvider` extension, which starts the same Swift HTTPS proxy tested through the Mac. The extension creates a P-256 authority unique to its installation and stores its certificate and key in its own Keychain access group, with `AfterFirstUnlockThisDeviceOnly` accessibility and synchronization disabled. The app never receives the private key. Storage errors do not silently generate a replacement authority.

The provider starts with eight maximum client connections. Setup mode serves the public certificate on a loopback HTTP endpoint without applying YouTube proxy settings. Filtering mode adds an HTTPS proxy for `youtubei.googleapis.com`, `youtubei-att.googleapis.com`, and `googlevideo.com` suffixes. There are no default IPv4/IPv6 routes, DNS interception, packet discard loop, remote VPN server, on-demand rules, or private API calls. Unrelated traffic is intended to remain outside this proxy scope.

**This routing strategy is experimental.** Apple's proxy-domain matching is documented for split tunnels, and Apple explicitly lists local proxies as an unsupported packet-tunnel use. It is unknown whether all relevant YouTube connections honor these settings on the target device. HTTP/3 and sockets that bypass system proxies are not captured. A successful VPN connection is not proof of filtering. [Proxy domain matching](https://developer.apple.com/documentation/networkextension/neproxysettings/matchdomains), [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)

The interface distinguishes setup, waiting for traffic, and received responses. Counters represent completed/rewritten responses, not prevented ads. Status messages contain only aggregates and the local public-certificate URL. No request URLs, cookies, video IDs, or payloads are persisted. A three-second status timeout prevents an unavailable provider from leaving the app waiting indefinitely.

## Development installation

1. Generate the project with `xcodegen generate --spec ios/project.yml` and open `ios/LocalFilter.xcodeproj` in compatible Xcode.
2. Select an activated developer team for **both** LocalFilter and LocalFilterTunnel. Automatic signing must provision their Network Extension capability. Keep team IDs, profiles, and account details out of source control. A pending enrollment or unsigned simulator build does not establish this capability.
3. Build and run on the paired test iPhone. Developer Mode is a development-installation requirement, not the intended end-user distribution flow.
4. **For an autonomous test, first turn off the old manual Wi-Fi proxy.** Record its previous setting for rollback. Otherwise the Mac can produce a misleading success.
5. In LocalFilter, choose **Prepare connection** and approve the iOS VPN-configuration prompt. This starts setup mode; it does not redirect YouTube yet.
6. Choose **Open certificate in Safari**. Install LocalFilter Personal CA through Settings → General → VPN & Device Management, then enable full trust in Settings → General → About → Certificate Trust Settings. This is a new device-local authority; the older Mac PoC certificate does not replace it.
7. Return to LocalFilter, confirm that trust was enabled, and choose **Enable filtering**. That confirmation is a user attestation, not an independent trust check.
8. Reopen the official YouTube app and choose several fresh videos. Confirm that the app receives traffic and reports rewriting. Compare actual playback with the displayed counts.

The app and embedded extension compiled successfully for the iOS simulator in [CI](https://github.com/Axel-KIRK/youtube-ios-local-filter/actions/runs/39145003403). A [local unsigned arm64 iPhone build](../evidence/local-ios-build.json) also succeeded after installing the iOS platform in Xcode 26.6. These steps are a test procedure, **not a report of a completed native installation**. At the time this increment was written, signing still awaited developer-program activation.

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
