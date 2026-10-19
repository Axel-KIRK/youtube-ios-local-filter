# Settings navigation, one level at a time

> Historical experiment. Later physical-phone destination checks are recorded in [the import follow-up](SHORTCUT-IMPORT.md). Build 3 uses the [manual guide](GUIDED-CERTIFICATE-SETUP.md); normal setup no longer imports or runs Shortcuts.

## Observed result

On October 19, 2026, real taps in LocalFilter's Debug screen reached every level below through a saved Shortcuts helper in the **iOS 26.5 simulator**:

| Level | Actual destination |
| --- | --- |
| General | **Général** |
| General → VPN & Device Management | **Gestion de l’appareil** |
| General → About | **Informations** |
| General → About → Certificate Trust Settings | **Réglages des certificats** |
| Pending certificate installation | **Profil**, the test certificate and **Installer**, without tapping the profile row |

Inspected screenshots show [trust settings](../evidence/settings-hierarchy-trust.png) and [the installation sheet opened by its URL](../evidence/settings-hierarchy-install.png). The test certificate was **not installed or trusted**. No VPN or YouTube test ran, and the physical phone was unchanged.

## Establish the caller before increasing depth

With Settings at its root, direct calls from LocalFilter to `App-prefs:root=General` and `App-prefs:General` were accepted but opened only main Settings. Direct `prefs:root=General` and `settings-navigation://com.apple.Settings.General` were rejected.

Passing `prefs:root=General` through Shortcuts reached General. The caller was then kept constant while changing the destination. No iCloud login or signed import was needed for this **local, manually authored diagnostic**; consumer shortcut distribution remains separate.

The helper is named **LocalFilter Profiles 1**, a duplicate of the earlier fixed profile-list test. It was edited through the Shortcuts UI, not injected into its database. Its actions are **Open URLs**, using **Shortcut Input**, followed by **Nothing**. The final action suppresses returned URL text and its output-permission prompt. The app's Debug screen supplies allowlisted test routes. This general URL-input helper is not the proposed consumer shortcut.

The first four successful destinations use:

```text
prefs:root=General
prefs:root=General&path=ManagedConfigurationList
prefs:root=General&path=About
prefs:root=General&path=About/CERT_TRUST_SETTINGS
```

## Find the last level with a pending profile

A one-day simulator-only CA was generated locally. Only its public DER certificate was served through loopback HTTP. Safari displayed **Profile Downloaded** after allowing the download; that dialog was closed before testing.

The older `ManagedConfigurationList/PurgatoryInstallRequested` path reached only the **list**, even with the pending profile present. Settings' own follow-up log contained:

```text
settings-navigation://com.apple.Settings.General/ManagedConfigurationList/DownloadedProfile?id=<complete-pending-profile-identifier>
```

Controlled comparisons through the same helper:

1. `DownloadedProfile` without an ID reached only the list.
2. The first extracted ID was incorrectly truncated to 64 hexadecimal characters. That URL also reached only the list.
3. The **complete 65-character ID**, taken from the simulator's actual follow-up URL, opened the installation sheet directly.

The sheet previously opened by hand for inspection had been dismissed. Both negative controls subsequently showed the list, so success was not restoration of that earlier sheet. The final screenshot was captured after a later observation, not during the app transition.

For this particular certificate, the identifier was the lowercase SHA-256 of its DER bytes **followed by `a`**. The initial fixed-length regex silently dropped this suffix. This is one observed sample, **not a cross-version identifier specification**. The app knows the certificate fingerprint, but deriving the pending-profile ID across systems still requires validation.

## Reproduce

Build and install the Debug app in an iOS simulator. Create the two-action helper above in Shortcuts, then launch:

```sh
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" \
  com.axelkirk.localfilter --settings-hierarchy-test --navigation-level=general
```

Tap **Open level through test shortcut** and inspect the Settings heading. Repeat with `profiles`, `about`, and `trust`. The direct-call buttons supply the first-level comparison. These are real in-app taps, not `simctl openurl` acting as another caller.

`--navigation-level=install` additionally exposes a simulator-only download button for `http://127.0.0.1:8899/LocalFilterNavigation.cer`. Serve only a synthetic public certificate there; keep the private key outside the HTTP directory. Allow its download and dismiss the confirmation. This level tests the older path.

Read the **complete** pending-profile ID from Settings' follow-up URL. Relaunch with `--navigation-level=downloaded` and `--navigation-profile-id=<observed-id>`, then tap **Open modern level through test shortcut**. Inspect the certificate-specific sheet and **Install** button without installing or trusting the test CA.

The harness is excluded from Release, does not construct the connection controller, and restricts IDs to the observed 64/65-character hexadecimal test inputs. The HTTP server was stopped afterward. The uninstalled downloaded profile can expire normally.

## Remaining limits

Physical iOS 18.6.1 behavior, signed import, more certificate identifiers and representative OS versions remain unverified. The simulator's profile-management UI differs from the phone's combined VPN/profile UI. The final URL is undocumented. Navigation never proves installation or trust: keep the actual TLS preflight before filtering.

See [structured evidence](../evidence/settings-hierarchy.json) and the [earlier experiment](SETTINGS-SHORTCUTS-EXPERIMENT.md).
