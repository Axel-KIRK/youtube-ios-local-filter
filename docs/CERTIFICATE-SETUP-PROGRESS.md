# Certificate setup progress

The old certificate screen always displayed **Download certificate** whenever the TLS check failed. That failure cannot distinguish a missing CA from an installed CA whose full trust is still disabled. An eight-minute timer also caused another download even when the user had already installed the profile.

## Current behavior

- The proxy emits `certificate_served` only after successfully flushing the public certificate response to a loopback client. The extension retains the timestamp across restarts, associated with the current public certificate's SHA-256 fingerprint.
- The app observes that receipt through provider status and remembers it across relaunches. A different CA clears previous progress. Merely opening Safari does not confirm delivery.
- After delivery, **Download certificate** is no longer the primary action. **2. Install certificate — show steps** and **3. Enable full trust — show steps** open separate numbered guides. Re-downloading remains available under **Certificate missing? / Need help?**, without regenerating the authority.
- Old builds recorded only that Safari opened. That legacy state offers continuation with explicitly conditional wording; it is not converted to a verified download, installation, or trust result.
- A saved receipt is not proof of an installed profile: Safari can reject the download, pending profiles can expire, and installed profiles can be removed. The app does not label installation complete based on a timestamp, navigation callback, or button tap.
- Returning to the app retries the existing real TLS preflight. Only that successful check permits filtering. No checkbox, custom trust anchor, or certificate-validation bypass is introduced.

Apple requires separate manual installation and full trust for a certificate downloaded this way. The eight-minute expiry concerns **uninstalled downloaded profiles**, not installed certificates. [Profile installation](https://support.apple.com/en-us/102400), [Certificate trust](https://support.apple.com/en-us/102390).

## Navigation and its current limit

Build 3 replaces the Shortcuts setup with a [manual guide](GUIDED-CERTIFICATE-SETUP.md), explicitly accepted by the user for this prototype. Normal setup does not create, import, or run shortcuts. Obsolete navigation-helper flags are removed on launch; those flags never represented certificate trust.

Each guide lists the exact menus and confirmation buttons. Instructions remain in English, with French Settings labels on a French phone. **Open Settings** uses `UIApplication.openSettingsURLString`, which opens app settings; the instructions explain returning to main Settings first. No direct certificate-submenu navigation is claimed.

Prepared helpers later reached both destinations on the physical phone, but signed consumer import was not established and the extra dependency was rejected. See the [historical import record](SHORTCUT-IMPORT.md). Debug-only navigation probes remain available for research.

## Reproduce

```sh
swift test --filter 'TransportTests|CertificateSetupProgressTests'
```

The setup tests cover a real public-certificate HTTP response and its delivery event, rejected download requests, persisted progress, certificate replacement, legacy migration, and Safari opening without a successful transfer. The existing TLS tests reject an untrusted CA and an unavailable proxy without falling back to a direct connection.

The Debug launch argument `--certificate-setup-preview` displays the same setup component without a VPN or changes to live setup preferences. Its clearly labeled synthetic controls exercise the missing-certificate, delivered-certificate, and replaced-CA screens. Its buttons open the same manual guides as the phone. Use `--guide-french` or `--guide-english` to check label layouts. This preview cannot validate profile installation, trust, or YouTube playback.

## Observed validation

On October 19, all **15 targeted tests passed**, and both simulator and signed iPhone Debug builds succeeded. The simulator preview visibly removed the primary download button after its delivery event and restored it for a replacement CA. Opening Safari alone did not advance it.

The updated app was installed and launched on the iPhone SE (3rd generation), iOS 18.6.1. A local screenshot showed **Finish certificate setup** and the two action buttons, without the primary download action. App preferences confirmed migration of the earlier Safari-open marker, rather than a newly observed download. Trust was still unverified and filtering remained off. The screenshot and raw preferences stay private.

At that earlier checkpoint, only the profile-list Shortcuts bridge had simulator evidence and the signing CLI required iCloud. See the historical [validation record](../evidence/certificate-setup-progress.json). The later [import record](SHORTCUT-IMPORT.md) records the subsequent physical-phone results and the decision to remove Shortcuts from normal setup.

A later [level-by-level navigation experiment](SETTINGS-HIERARCHY-EXPERIMENT.md) reached General, the profile list, About, certificate trust settings, and the exact installation sheet in the iOS 26.5 simulator. Build 3 subsequently passed simulator and signed-device compilation and was installed on the test phone. Its new numbered setup buttons were observed there; completing installation, trust, and autonomous playback remains a separate trial.
