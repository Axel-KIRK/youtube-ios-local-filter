# Historical navigation-helper import experiment

Status: retired from normal setup in Build 3. The user rejected a dependency on
Shortcuts and accepted a clear manual guide for the prototype. See the
[current guide](GUIDED-CERTIFICATE-SETUP.md).

## Why the old screen persisted

The app installed after commit `e0a0d33` contained a hierarchy diagnostic, but
normal setup still displayed instructions for adding navigation helpers. No
usable import asset was supplied in that build. Installing the diagnostic did
not complete the normal setup flow.

## October 19, 2026 observations

1. A temporary UIKit document-import component handed a deliberately unsigned
   file to Shortcuts in the iOS 26.5 simulator. Shortcuts rejected the unsigned
   import. This was a negative control, not a successful distribution test.
2. The Mac signing CLI first required an iCloud session. After the user completed
   the actual System Settings sign-in, two signing attempts failed with
   `NSURLErrorDomain` code `504`. The earlier missing-session diagnosis no
   longer described that later failure.
3. Two fixed helpers were created in the Mac Shortcuts app: **LocalFilter
   Profiles** and **LocalFilter Trust**, each opening its Settings destination
   and returning no output. A URL edit required committing the edit before the
   saved action changed. Apple sharing links were created through the UI.
4. Simulator gallery import failed to connect. A physical-phone link showed a
   loading state, without a verified completed import. Therefore consumer
   installation through a shared link or signed file was not demonstrated.
5. iCloud synchronization delivered the prepared helpers to the test iPhone SE
   (3rd generation), iOS 18.6.1. Build 2's isolated diagnostic invoked them.
   Observed headings were **VPN et gestion de l’appareil** and **Réglages des
   certificats**. These establish the two destinations with existing helpers,
   not a clean consumer import flow or support for every iOS version.
6. The phone showed only the old Mac-test certificate; **LocalFilter Personal
   CA** was absent. These navigation tests did not install or trust the new CA.
7. The user rejected the helper dependency. Build 3 removes import/run controls
   and their remembered flags from normal setup. No shortcut assets or Apple
   sharing links are bundled. Existing test helpers were not deleted from the
   user's Shortcuts library; the app no longer uses them during normal setup.

The temporary document-import implementation and its launch harness were
removed. Debug-only navigation research and the source generator remain as
historical experiments. Do not interpret their presence as a product dependency
or a signed deliverable. Public evidence contains no account-associated sharing
links, phone screenshots, device identifiers, or signing metadata.

## References

- [Apple: distributing shortcuts](https://developer.apple.com/videos/play/wwdc2021/10232/)
- [Apple: command-line signing](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac)
- [Level-by-level destination experiment](SETTINGS-HIERARCHY-EXPERIMENT.md)
