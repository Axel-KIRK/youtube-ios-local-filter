# Settings navigation through Shortcuts

## Observed result

On the **iPhone SE simulator running iOS 26.5 (23F77)**, a real tap in LocalFilter opened **Settings → General → Device Management** through a saved shortcut. The visible French title was **Gestion de l’appareil**, with an empty profile list. Settings had first been returned to its root screen, so this was destination navigation rather than restoration of the last screen.

```text
LocalFilter button
  → shortcuts://run-shortcut?name=LocalFilter%20Profiles
  → saved shortcut's Open URLs action
  → prefs:root=General&path=ManagedConfigurationList
  → Device Management
```

The first shortcut returned the URL text after opening Settings, which caused a delayed permission prompt when launched from LocalFilter. A final **Nothing** action removes this unnecessary output. After this change, a new tap from LocalFilter reached the target and a later UI observation and screenshot still showed the destination without the prompt. No output-permission approval was clicked. Do not count the initial destination transition alone as a complete prompt-free flow. [Final simulator screenshot](../evidence/settings-shortcuts-profiles-simulator.png).

The same `prefs:` destination was rejected by direct calls from LocalFilter in the earlier audit. Safari also rejected all three tested profile-list schemes (`prefs`, `App-prefs`, and `settings-navigation`) as invalid addresses. The caller therefore matters: direct-app failures do not establish that navigation through Shortcuts also fails.

This result is limited to the simulator. It does not demonstrate the physical phone's combined VPN/profile UI, pending-profile installation, certificate trust, or filtering. See the [structured evidence](../evidence/settings-shortcuts-bridge.json) and [direct-call audit](../evidence/settings-navigation-audit.json).

## Reproduce locally

1. In the simulator's Shortcuts app, create a shortcut with **Open URLs** and the literal `prefs:root=General&path=ManagedConfigurationList`, followed by **Nothing**.
2. Name it exactly **LocalFilter Profiles**, then return to the shortcut library to save it.
3. Return Settings to its root page.
4. Launch a Debug build of LocalFilter with `--settings-shortcuts-test`.
5. Tap **Open profiles with shortcut** and inspect the actual destination.

The isolated Debug screen does not construct the connection controller. Its separate **Copy link and create shortcut** button helps prepare a manual diagnostic by copying only the fixed URL and opening the documented Shortcuts editor. This manual creation flow is not the proposed consumer onboarding. All navigation probes remain excluded from Release.

## Preparing an Add Shortcut flow

The consumer candidate is a prepared shortcut that the user approves once, followed by LocalFilter buttons that run it. The generator prepares a fixed **URL → Open URLs → Nothing** source equivalent in purpose to the **Open URLs → Nothing** shortcut created in the UI:

```sh
python3 scripts/build-navigation-shortcut.py
python3 scripts/build-navigation-shortcut.py --sign
python3 scripts/build-navigation-shortcut.py --destination trust
```

The unsigned file is not a ready-to-install deliverable. Apple's signing command failed on the current Mac with **“In order to do this, you must be signed into iCloud.”** An Apple Developer/Xcode login is not evidence of an iCloud session. The generated file's signed import and execution have not been validated. No signing credentials or account details are committed.

Apple documents distributing notarized shortcuts through iCloud links or signed files, and launching saved shortcuts from another app using `shortcuts://run-shortcut`. The signing prerequisite is a build/distribution issue; the proposed user flow must not ask consumers to construct the shortcut or use developer tools. See [Apple's Shortcuts distribution session](https://developer.apple.com/videos/play/wwdc2021/10232/), [command-line signing](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac), and [running a saved shortcut by URL](https://support.apple.com/guide/shortcuts/apd624386f42/ios).

The generator now also prepares a **LocalFilter Trust** candidate for `prefs:root=General&path=About/CERT_TRUST_SETTINGS`. A subsequent [level-by-level experiment](SETTINGS-HIERARCHY-EXPERIMENT.md) validated that destination through a saved input-based helper, and reached the exact pending-profile installation sheet using its complete identifier. Signed import remains untested. The app's current progress fix and explicit navigation fallback are described in [certificate setup progress](CERTIFICATE-SETUP-PROGRESS.md).

## Other approaches checked

- Searching native-app source found the same legacy profile paths already tested, rather than a demonstrated replacement. For example, [capacitor-native-settings](https://github.com/RaphaelWoude/capacitor-native-settings/blob/main/ios/Sources/NativeSettingsPlugin/NativeSettings.swift) contains `App-prefs:General&path=ManagedConfigurationList`. Presence in source is not proof it works on current iOS.
- [Reports from the Settings URL collector](https://github.com/FifiTheBulldog/ios-settings-urls/issues/71) describe the same root-only behavior since iOS 18. The [Shortcuts-based settings launcher](https://github.com/OnCloud125252/ios-settings-launcher) suggested testing a different caller; the local UI test above supplies our own evidence.
- `OpenURLIntent` does not provide a documented substitute for the saved shortcut: Apple requires a universal link and explicitly excludes custom URL schemes. Returning the operation to the app's ordinary URL opener would reintroduce the direct-call path. See [OpenURLIntent](https://developer.apple.com/documentation/appintents/openurlintent).

## Remaining acceptance checks

Validate signed-file import, the native bridge on the physical iOS 18 phone, the installer and trust destinations, renamed/missing shortcuts, permission prompts, and representative newer iOS versions. Count all first-run and subsequent taps. Keep the experiment out of normal setup until it is simpler and reliable enough for the consumer requirement. Neither a successful launch callback nor a navigation result proves that a certificate was installed or trusted; the TLS preflight remains mandatory.
