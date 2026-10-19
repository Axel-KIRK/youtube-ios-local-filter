# Compatibility requirements and test matrix

## Target

The initial consumer target starts with the existing test phone, an **iPhone SE (3rd generation) running iOS 18.6.1**, and extends to newer iPhones and newer iOS versions. This is a target, not a claim that all combinations work. The project's iOS 17 deployment target is a build setting; it does not establish tested support for iOS 17.

Setup must remain a sequence of primary actions and system approvals, without finding Settings menus or reading a technical guide. A working shortcut on one iOS version does not satisfy that requirement on other versions. Navigation behavior depends on the OS; hardware, screen size, background execution, and resource use also need device checks.

## Current evidence

| Environment | What was checked | Result and limit |
| --- | --- | --- |
| iPhone SE (3rd generation), iOS 18.6.1 | Signed installation, setup mode, missing-certificate TLS guard, pending setup resume and cancellation | Verified for those operations; autonomous ad removal remains unverified. |
| Same physical phone, iOS 18.6.1 | Experimental downloaded-profile URL with no visible pending download | Opened the main Settings screen. This is not direct installation. |
| Same physical phone, iOS 18.6.1 | Experimental URL immediately after a fresh profile download, then again after the user dismissed the download confirmation | Both attempts opened the main Settings screen with Profile Downloaded visible. Neither opened the installation sheet. Dismissing the confirmation did not change the destination. |
| Same physical phone, iOS 18.6.1 | Debug button after a new download | User confirmed the button changes and opens Settings, but explicitly rejected root Settings as meeting the request. The exact installation submenu must open. Installation and trust remain separate checks. |
| iPhone SE simulator, iOS 26.5 | Welcome and guide layout | Main action fits on the initial screen. This does not validate a physical device's VPN or YouTube playback. |
| Same simulator, iOS 26.5 | Experimental downloaded-profile URL, no pending profile | `App-prefs:` opened main Settings; `prefs:` was rejected. Direct installation was not demonstrated. |
| Same simulator, iOS 26.5 | Additional direct-navigation candidates from LocalFilter | `settings-navigation:` links for DownloadedProfile, its profile-list parent, and General were rejected (`open` returned false); the rootless `App-prefs:General&path=…` variant opened main Settings. No pending profile was present. The physical-device results are recorded separately below. |
| Same physical phone, iOS 18.6.1 | Modern profile, profile-list parent and General routes; rootless legacy variant | All three modern routes were rejected (`open` returned false). The rootless legacy variant opened main Settings both without a pending profile and after a fresh download, with Profile Downloaded visibly present and no dialog covering the screen. Neither attempt opened installation. |
| Other physical iPhones and newer iOS releases | Setup, trust, local transport, playback, background operation | Not yet tested. |

No row represents a general promise of compatibility with future iOS releases. Record the exact OS build, device model, app revision, expected destination, and observed destination for each test. Keep device identifiers and screenshots containing personal information out of the public repository.

## Shortcut acceptance

Opening a URL successfully is not proof that it reached the intended screen. Check the actual destination with a fresh pending download, after dismissal of the download dialog, after cancellation, and after the pending profile expires. Test both returning from Settings and relaunching LocalFilter. Never treat download launch or a navigation result as proof of installation or trust; the real TLS check must still pass before filtering starts.

The public app-settings link does not open certificate installation. Undocumented schemes are experiments only: Apple states that they are unsupported and may stop working. A shortcut that opens the wrong screen must not be labeled as a verified direct link. A manual fallback can keep the prototype usable, but does not pass the consumer onboarding requirement. [Apple's supported URL schemes](https://developer.apple.com/forums/thread/761314), [Profile download expiry and installation](https://support.apple.com/en-us/102400).

### Current Debug experiment

The first candidate was `App-prefs:root=General&path=ManagedConfigurationList/PurgatoryInstallRequested`. A temporary Debug button changed from **Download certificate** to **Continue in Settings** after the download URL opened. The user confirmed that this opened root Settings but explicitly rejected it as satisfying the request. **That button was removed from normal setup. The exact installation submenu remains the acceptance criterion.**

Debug launch probes retain the experiments without exposing a nonworking installer button. Run `--probe-install-profile` with optional `--profile-route=without-root`, `modern-profile`, `modern-profiles`, or `modern-general`; the default is `legacy-root`. Only fixed route names and open-result booleans are logged. These are bounded diagnostic candidates, not a general URL launcher. Release excludes the probe and all candidate URLs. Real TLS verification still gates filtering, independently of download or navigation results.

The modern profile link, its parent and General routes were rejected on both the iOS 26.5 simulator and physical iOS 18.6.1 phone; the rootless legacy candidate opened main Settings on both. A physical-device retry of the rootless candidate with a fresh pending download also reached main Settings, not installation. Absence of a pending profile limits successful-navigation tests; a rejected URL is recorded separately from an accepted URL that reaches the wrong destination.

## YouTube version coverage — later phase

Cross-version YouTube playback testing is deliberately deferred until the native setup and basic playback trial are complete, as requested by the user.

Record exact YouTube version/build numbers; cover the current officially available version and older versions available through legitimate test/distribution channels. Test main-video startup, multiple selections, pre-roll and mid-roll ads, skipping, seeking, cancellation, and unknown-response fallback. Record both stalled playback and remaining ads. A synthetic fixture passing or a rewritten-response counter alone is not proof of ad-free playback. Server-delivered response changes must be considered separately from the installed app version.

Validate representative newer hardware, Wi-Fi and cellular, lock/resume, extension memory, and recovery after Stop before declaring a supported combination. Keep OS navigation compatibility and YouTube response compatibility as separate results.

Candidate provenance: the rootless prefix variant is described by the [Settings URL collector](https://github.com/FifiTheBulldog/ios-settings-urls). The modern downloaded-profile URL appears in an [iOS 26 system-library string diff](https://github.com/blacktop/ipsw-diffs/blob/main/26_0_23A5297i__vs_26_0_23A5308g/DYLIBS/MDMClientLibrary.md). The modern parent and General routes are diagnostic simplifications of that path, not documented public APIs. Presence in system files does not establish third-party access.

## Comparison with existing proxy apps

Proxyman's [native iOS setup guide](https://proxyman.com/posts/2021-10-17-Getting-Started-With-Proxyman-For-iOS) documents downloading, installing and trusting its certificate in Settings, followed by a return to the app to verify readiness. Charles for iOS similarly tells users to follow its certificate installation/trust instructions in its [getting-started guide](https://www.charlesproxy.com/documentation/ios/getting-started-1/). These published workflows do not establish a direct installer link we can reuse. This is a documentation comparison, not a hands-on test of their latest app releases.
