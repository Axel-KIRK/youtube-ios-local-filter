# Certificate setup progress

The old certificate screen always displayed **Download certificate** whenever the TLS check failed. That failure cannot distinguish a missing CA from an installed CA whose full trust is still disabled. An eight-minute timer also caused another download even when the user had already installed the profile.

## Current behavior

- The proxy emits `certificate_served` only after successfully flushing the public certificate response to a loopback client. The extension retains the timestamp across restarts, associated with the current public certificate's SHA-256 fingerprint.
- The app observes that receipt through provider status and remembers it across relaunches. A different CA clears previous progress. Merely opening Safari does not confirm delivery.
- After delivery, **Download certificate** is no longer the primary action. **Install LocalFilter Personal CA** and **Turn on full trust** are separate buttons. Re-downloading remains available under **Need help?**, without regenerating the authority.
- Old builds recorded only that Safari opened. That legacy state offers continuation with explicitly conditional wording; it is not converted to a verified download, installation, or trust result.
- A saved receipt is not proof of an installed profile: Safari can reject the download, pending profiles can expire, and installed profiles can be removed. The app does not label installation complete based on a timestamp, navigation callback, or button tap.
- Returning to the app retries the existing real TLS preflight. Only that successful check permits filtering. No checkbox, custom trust anchor, or certificate-validation bypass is introduced.

Apple requires separate manual installation and full trust for a certificate downloaded this way. The eight-minute expiry concerns **uninstalled downloaded profiles**, not installed certificates. [Profile installation](https://support.apple.com/en-us/102400), [Certificate trust](https://support.apple.com/en-us/102390).

## Navigation and its current limit

The intended buttons run saved shortcuts named **LocalFilter Profiles** and **LocalFilter Trust**. Each contains only a fixed Settings destination followed by **Nothing**, with no credentials, incoming arbitrary URL, or returned output. Generated source uses **URL → Open URLs → Nothing**.

Normal setup does not blindly run a shortcut that has never been added. A build can supply reviewed Apple import links in `ios/App/SettingsShortcuts.plist` using keys `profiles` and `trust`. The import UI explains the one-time addition; the user can then continue. If no distributable shortcut is supplied, the button explicitly shows the manual Settings path. That fallback does **not** meet the requested automatic navigation goal.

The remembered shortcut flag is only the user's confirmation that they added a navigation helper. It is unrelated to certificate trust. If a shortcut was removed or renamed, use **Help and diagnostics → Set up navigation buttons again**. The OS callback can confirm that Shortcuts opened, not that a named shortcut exists or reached its destination.

Signed distribution requires an iCloud session on the build Mac; the Developer Program/Xcode account alone does not satisfy this requirement. Generated unsigned files must not be presented as importable deliverables. See the [navigation experiment](SETTINGS-SHORTCUTS-EXPERIMENT.md) for the tested routes and remaining platform checks.

## Reproduce

```sh
swift test --filter 'TransportTests|CertificateSetupProgressTests'
python3 scripts/build-navigation-shortcut.py --destination profiles
python3 scripts/build-navigation-shortcut.py --destination trust
```

The setup tests cover a real public-certificate HTTP response and its delivery event, rejected download requests, persisted progress, certificate replacement, legacy migration, and Safari opening without a successful transfer. The existing TLS tests reject an untrusted CA and an unavailable proxy without falling back to a direct connection.

The Debug launch argument `--certificate-setup-preview` displays the same setup component without a VPN or changes to live setup preferences. Its clearly labeled synthetic controls exercise the missing-certificate, delivered-certificate, and replaced-CA screens. Its navigation buttons run the actual saved shortcuts; inspect the resulting Settings heading, not just the URL callback. This preview cannot validate profile installation, trust, or YouTube playback.

## Observed validation

On October 19, all **15 targeted tests passed**, and both simulator and signed iPhone Debug builds succeeded. The simulator preview visibly removed the primary download button after its delivery event and restored it for a replacement CA. Opening Safari alone did not advance it.

The updated app was installed and launched on the iPhone SE (3rd generation), iOS 18.6.1. A local screenshot showed **Finish certificate setup** and the two action buttons, without the primary download action. App preferences confirmed migration of the earlier Safari-open marker, rather than a newly observed download. Trust was still unverified and filtering remained off. The screenshot and raw preferences stay private.

The profile-list Shortcuts bridge has earlier simulator evidence. The trust bridge is only a prepared source candidate. Neither has a validated signed-import flow on this phone. The signing CLI still reported that the Mac needed an iCloud session. See the [validation record](../evidence/certificate-setup-progress.json); do not report this increment as completed consumer onboarding.
