# Standalone iOS application

## User goal

Install an app, follow a few clearly explained confirmations in Settings, enable the filter, and continue using the official YouTube app. The end user should need no Mac, terminal, Developer Mode, or modified YouTube application. This repository targets **iOS only**.

This setup is the goal; the validated prototype still depends on a Mac. TestFlight/App Store distribution is separate from compilation and development installation.

## Separate responsibilities

1. **Local rewriting engine**: decode Protobuf and UMP, authenticate Onesie, remove the three advertising fields, preserve media, and return the original on error. Port this component to Swift and test it independently of networking.
2. **Transport**: obtain YouTube HTTPS responses in an iOS process that continues running while YouTube is in the foreground. Preserve upstream certificate verification, memory limits, HTTP streaming, and non-targeted connections.
3. **Local certificate**: an authority unique to each installation, a private key stored in Keychain, export of the public certificate only, and explicit installation and trust by the user.
4. **Interface**: a few steps, accurate status (ready, inactive, error), an accessible stop control, and no counters misleadingly presented as a number of ads prevented.

Domain blocking and video-ID media filtering should not become the app's primary mechanism: they failed to ensure ad-free playback in the prototype.

## Standalone proxies already exist on iOS

**An app can provide a local HTTPS proxy without a Mac.** Charles for iOS and Proxyman for iOS document this behavior and App Store distribution. Charles asks the user to authorize a VPN configuration, then install and trust its certificate. Proxyman explains that its VPN routes traffic to an MITM server on the phone. These examples establish the feasibility of a standalone proxy; they do not yet validate our YouTube rewriting in that environment. [Charles setup](https://www.charlesproxy.com/documentation/ios/getting-started-1/), [Proxyman architecture and certificate](https://github.com/ProxymanApp/docs/blob/main/proxyman-ios/vpn-and-proxyman-certificate.md)

The intended setup is therefore: install our app, authorize its VPN configuration, install and trust its certificate once, then enable the filter. YouTube is not reinstalled. A normally distributed release does not require Developer Mode; that mode relates to development testing and diagnostics.

## Networking work still needed in our code

An ordinary app does not automatically receive other apps' HTTPS responses. A Safari content blocker does not handle the official YouTube app's traffic. URL or domain filtering alone does not provide the Protobuf body rewriting needed here.

`NEPacketTunnelProvider` is a technical avenue to investigate. Apple nevertheless states that using it as a content filter or to host a local proxy is outside its supported use cases. This documentation constraint **does not establish technical impossibility or a ban on all iOS proxies**, as existing apps demonstrate. Practical behavior, officially supported architecture, and acceptance of our own product must be distinguished. Deployment constraints of other Network Extension providers also need checking. [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers), [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)

A VPN to a remote server would be a different architecture, with server costs and traffic leaving the device; it is not the intended local design and is not deployed by this project. A proxy in the main app that disappears when iOS suspends it would also fail to meet the requirement.

Trusting a manually installed certificate requires an action in Settings. The app can guide this step, but cannot hide it or silently enable trust. [Apple certificate trust instructions](https://support.apple.com/en-us/102390)

## Criteria for an initial usable release

- The Swift engine passes the same synthetic fixtures as the Python engine, including encrypted and fragmented responses.
- The transport remains operational while YouTube is in the foreground and across lock/resume.
- The certificate key stays on the device; installations do not share an authority; personal requests are not collected.
- A first launch without a key, key renewal, and an unknown schema still allow playback; the interface makes any absence of filtering visible.
- Someone who did not participate in development can configure a second personal iPhone without a Mac or Developer Mode.
- Pre-roll and mid-roll ads, multiple sessions, and multiple YouTube versions are tested. Errors and remaining ads are recorded with the relevant context.
- Signing, Apple capabilities, and the distribution channel are validated before an installation link is offered. [VPN distribution rules](https://developer.apple.com/app-store/review/guidelines/#vpn-apps)

## Implementation sequence

The first increment ported the real engine to Swift and created a local verification app, compiled for the iOS simulator. It shows “Filter inactive” until it can access YouTube traffic. Network integration and distribution are the next milestone; a VPN shell that accepts a connection but forwards no packets would be a defect, not progress. See the [implementation status and checks](DEVELOPMENT.md).
