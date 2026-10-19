# Guided certificate setup — Build 3

The current prototype uses numbered instructions inside LocalFilter. It does
not create, import, or run Shortcuts during normal setup. The user accepted this
manual navigation approach after the direct-link and helper experiments.

Instructions are in English. Menu names match French Settings when the phone's
preferred language is French, otherwise English. Only these two sets of labels
have been reviewed; other languages and other physical iOS versions are not
validated. The app targets iOS 17+, which is not a compatibility guarantee.

## Download

1. Start **Set up and enable**, approving the local VPN configuration if needed.
2. Tap **1. Download certificate**. If an earlier download is remembered but the
   certificate is missing, use **Certificate missing? / Need help? → Download
   certificate again**.
3. Safari: **Allow / Autoriser**, then **Close / Fermer**.
4. Return to LocalFilter and tap **2. Install certificate — show steps**.

The app remembers a successful certificate response, not just opening Safari.
A download receipt does not prove that the profile was installed. Uninstalled
pending profiles expire after eight minutes; an installed certificate does not
need repeated downloads. A replacement CA resets the saved progress.

## Install

**English:** Settings → General → VPN & Device Management → LocalFilter Personal
CA → Install.

**French:** Réglages → Général → VPN et gestion de l’appareil → LocalFilter
Personal CA → Installer.

Use the Install button at the top right. Enter the iPhone passcode if requested,
confirm Install on subsequent screens, and finish with Done / Terminé. If
Profile Downloaded / Profil téléchargé appears on the main Settings screen, it
is a shorter route to the downloaded profile.

Select the exact **LocalFilter Personal CA** name. The old YouTube PoC certificate
belongs to the previous Mac proxy and does not complete native setup. If the
new name is missing, return to the app, download again, and install promptly.
If already installed, continue to full trust instead of downloading again.

## Enable full trust

Return to LocalFilter and tap **3. Enable full trust — show steps**, or use
**Next: enable full trust** at the bottom of the installation guide.

**English:** Settings → General → About → Certificate Trust Settings.

**French:** Réglages → Général → Informations → Réglages des certificats.

Scroll to the bottom of About / Informations. Enable the switch next to
**LocalFilter Personal CA** and approve Continue / Continuer if requested. This
allows LocalFilter to read and modify scoped YouTube HTTPS responses on this
phone. If the switch is missing, install the profile first.

Return to LocalFilter from the Home Screen. It retries the real TLS and
connection check while setup is pending. Only a successful check enables
filtering and displays **Ready for YouTube**. Opening a guide, tapping Next, or
returning from Settings never proves trust. **Check my setup** retries the same
check. **Cancel setup** stops pending activation.

## What Open Settings does

The guide uses Apple's `UIApplication.openSettingsURLString`. This opens the
app's Settings page, not an arbitrary certificate submenu. The instructions
explicitly say to use the top-left back arrow until reaching main Settings,
then follow the numbered path. Opening Settings from the Home Screen is also
available. There is no promised direct profile-installer link.

## Verification on October 19, 2026

- Debug simulator compilation and signed physical-device compilation passed.
- Build 3 was installed and launched on the iPhone SE (3rd generation), iOS
  18.6.1 (22G90). A private screenshot confirmed the new setup buttons and no
  Shortcuts instructions. The screen still required certificate approval.
- The French-label guides were checked in the SE-size iOS 26.5 simulator. Actual
  button actions opened the installation guide, advanced to full trust, and
  returned to installation. Open Settings launched Settings. Simulator preview
  does not start a VPN or validate real certificate trust.
- No rewrite-engine or transport behavior changed in this update. Earlier
  targeted transport/setup test results are preserved separately; compilation
  and UI checks for this update do not establish autonomous ad removal.
- End-to-end profile installation, full trust, fresh YouTube playback, and
  observed response/rewrite counters remain pending in this guided trial.

## Complete the device trial

Follow the guide on the physical phone. Record the reached screen and any
ambiguous instruction. After **Ready for YouTube**, fully close YouTube, reopen
it, and select several fresh videos. Record ads, stalls, playback progress, and
aggregate received/rewritten/error counters. Check recovery with **Stop
filtering** if playback fails. A ready indicator alone or a nonzero rewrite
counter is not proof that ads were removed.

Do not publish raw screenshots, profile payloads, private keys, device IDs,
authenticated URLs, or account details. Keep only sanitized outcomes in
[evidence](../evidence/guided-certificate-setup.json).

## Apple references

- [Install a downloaded profile](https://support.apple.com/en-us/102400)
- [Trust an installed certificate](https://support.apple.com/en-us/102390)
- [Open app settings](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)
