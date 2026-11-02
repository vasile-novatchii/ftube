# Release checklist

Run through this before pushing a `vX.Y.Z` tag (docs/spec.md section 6, DoD-8).

## Once per repo

- [ ] Create the Android release key and add it as repository secrets, so every APK has the same signature and updates install over each other:

  ```bash
  keytool -genkeypair -v -keystore ftube-release.jks -alias ftube \
    -keyalg RSA -keysize 4096 -validity 10000
  base64 -i ftube-release.jks | gh secret set FTUBE_KEYSTORE_BASE64
  gh secret set FTUBE_KEYSTORE_PASSWORD
  gh secret set FTUBE_KEY_ALIAS --body ftube
  gh secret set FTUBE_KEY_PASSWORD
  ```

  Keep the `.jks` file and passwords outside the repo. Without these secrets the workflow signs the APK with a throwaway debug key and warns.

## Before the tag

- [ ] `version:` in `pubspec.yaml` is `X.Y.Z+N`, with `N` higher than the last release (Android `versionCode`).
- [ ] CI is green on `main`: analyze, format, tests, coverage gate.
- [ ] `assets/binaries/catalog.json` points at a published `binaries-rN` pre-release, and the `Binaries` workflow is green.

## Manual checks

Desktop, on each of macOS, Windows and Linux, with a fresh app support folder:

- [ ] First launch downloads the binaries and reaches the Home screen.
- [ ] A short download as video and as MP3 lands in `Downloads/Ftube`.
- [ ] Library opens, reveals, renames, converts and deletes the file, and Undo restores it.
- [ ] A confirmed delete shows the 5s countdown, and once it ends the file is in the system bin (Trash, Recycle Bin, `~/.local/share/Trash`) (DoD-14).
- [ ] macOS: on macOS 12 and on the latest macOS, the zip opens after the README `xattr` step, and the downloaded binaries run without a quarantine prompt (R-7).
- [ ] macOS: `lipo -archs Ftube.app/Contents/MacOS/ftube` reports `x86_64 arm64`, and first launch works on Apple silicon and on Intel (DoD-10).

Android, on an emulator or device at API 31 and at the latest API:

- [ ] Deny All files access: the permission screen stays and explains why. Grant it: Home opens.
- [ ] A high-quality video download and an MP3 download land in `Download/Ftube`.
- [ ] Library opens and shares a file through another app.
- [ ] Uninstall, reinstall and grant access again: the old files are listed and can be deleted one by one, selected, and all at once.

## v0.2 checks

docs/spec-v0.2.md section DoD, on top of the checks above.

Desktop, on each of macOS, Windows and Linux:

- [ ] The window opens at 800×600, the edges don't resize it (Linux keeps an 800×600 minimum, R-13), and maximize fills the screen with no overflow (DoD-12). On Linux, check maximize on GNOME and KDE.
- [ ] The app shows the new icon in the dock or taskbar and is titled "Ftube Downloader" (DoD-17).

Android, at API 31 and at the latest API:

- [ ] Portrait, landscape, split screen and a pop-up window show no overflow, and a half-typed link and the queue survive rotation and resizing (DoD-13).
- [ ] Delete to the bin: note whether a system "move to bin?" dialog follows the app's confirm (R-12). The file is in the Files app's bin after the countdown.
- [ ] The adaptive and themed (monochrome) icons look right, the label is "Ftube Downloader", and v0.2 installs over v0.1 without losing files or settings (DoD-17).

Everywhere:

- [ ] Settings opens twice in a row and the tool versions are checked once; updating yt-dlp checks again (DoD-11).
- [ ] The link field shows the clear button only while it has text (DoD-15).
- [ ] Clear app data during a download is disabled. After a download, it empties the library, the files stay on disk, settings stay, and the items don't come back after a restart or a refresh (DoD-16).
- [ ] Switch to each of the six languages: nothing is left in English, and Arabic lays out right to left (DoD-18).
- [ ] A native speaker has reviewed the RU, ES, DE and AR texts (R-15).

## After the tag

- [ ] The `Release` workflow is green. Read the `Smoke download` step on each OS; it may only warn when YouTube blocks the runner.
- [ ] The release has the macOS `.zip`, Windows `.zip`, Linux `.tar.gz` and three Android APKs (`-arm64-v8a`, `-armeabi-v7a`, `-x86_64`, about 19-28MB each), and the job summaries show their sizes. The run also has an `android-symbols-*` artifact; download it before it expires (90 days) and keep it to read obfuscated crash traces with `flutter symbolize`. Note the desktop size cost of the unused FFmpegKit libraries (R-5).
- [ ] Each archive contains `LICENSE` and `THIRD_PARTY_NOTICES.md`.
