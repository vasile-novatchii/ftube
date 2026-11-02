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
- [ ] macOS: on macOS 12 and on the latest macOS, the zip opens after the README `xattr` step, and the downloaded binaries run without a quarantine prompt (R-7).
- [ ] macOS: `lipo -archs Ftube.app/Contents/MacOS/ftube` reports `x86_64 arm64`, and first launch works on Apple silicon and on Intel (DoD-10).

Android, on an emulator or device at API 31 and at the latest API:

- [ ] Deny All files access: the permission screen stays and explains why. Grant it: Home opens.
- [ ] A high-quality video download and an MP3 download land in `Download/Ftube`.
- [ ] Library opens and shares a file through another app.
- [ ] Uninstall, reinstall and grant access again: the old files are listed and can be deleted one by one, selected, and all at once.

## After the tag

- [ ] The `Release` workflow is green. Read the `Smoke download` step on each OS; it may only warn when YouTube blocks the runner.
- [ ] The release has the macOS `.zip`, Windows `.zip`, Linux `.tar.gz` and three Android APKs (`-arm64-v8a`, `-armeabi-v7a`, `-x86_64`, about 19-28MB each), and the job summaries show their sizes. The run also has an `android-symbols-*` artifact; download it before it expires (90 days) and keep it to read obfuscated crash traces with `flutter symbolize`. Note the desktop size cost of the unused FFmpegKit libraries (R-5).
- [ ] Each archive contains `LICENSE` and `THIRD_PARTY_NOTICES.md`.
