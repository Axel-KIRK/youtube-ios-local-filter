# Apple signing and distribution status

Checked against Apple's documentation on October 18, 2026. **Device provisioning and App Store acceptance are not yet validated for this product.** The developer's enrollment is pending activation; Xcode currently shows only a Personal Team after sign-in. Personal account details and the enrollment reference are intentionally not part of this public repository.

## Testing and signing

A free Apple account can test ordinary apps on a personal device through Xcode, with short-lived provisioning. Advanced capabilities depend on membership. The planned Network Extension needs eligible provisioning; the Swift engine, desktop HTTPS proxy, and unsigned simulator build can be tested without that device provisioning. An enrollment reference is not the signing Team ID: obtain the actual team from the activated account or Xcode. [Account overview](https://developer.apple.com/help/account/basics/about-your-developer-account), [iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios)

The development Mac currently runs macOS 26.4. The current App Store Xcode requires macOS 26.6. Xcode 26.6, available from Apple's older downloads, supports macOS 26.2 and later in the 26.x family and can target the test phone's iOS version. Xcode 26.6 was installed and its license accepted by the developer. This avoids requiring a system update for development. Download and signing authentication happen directly with Apple. [Xcode requirements](https://developer.apple.com/xcode/system-requirements), [Apple downloads](https://developer.apple.com/download/all/?q=Xcode%2026.6)

## App Store assessment

Guideline 5.4 requires organization enrollment for apps offering VPN services and imposes data disclosure/privacy requirements. It also allows approved content-blocking and security providers to use the VPN API. Our classification and eligibility have not been confirmed. An individual membership enabling development would not, by itself, establish App Store eligibility. Guideline 5.5 also addresses apps offering configuration profiles; how certificate installation is packaged needs review. Guideline 2.5.4 limits background services to their intended purposes. No submission or approval has occurred. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#vpn-apps)

Apple's TN3120 explicitly describes local listeners/proxies and content filtering as unsupported packet-tunnel uses. Existing local proxy apps show technical feasibility, but they are not approval for this architecture or this YouTube modification. The proposed transport must be tested on a device, and the distribution decision remains separate. [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers), [Architecture and existing examples](IOS-ARCHITECTURE.md)

Before release, establish a working signed extension, accurate data disclosures, per-device key protection and certificate removal instructions, a suitable developer account, and App Review acceptance. Do not market the current project as an install-and-enable product, or claim that paying the membership guarantees distribution.
