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

## v0.3 checks

docs/spec-v0.3.md section DoD, on top of the checks above.

Android, with the release APK (R8 is on, unlike debug builds), on a 16KB-page emulator and on an Android 12 device:

- [ ] A 1080p YouTube video over 100MB downloads in full and plays with sound (DoD-20).
- [ ] MP3 and OGG downloads play, and cancel stops the download and leaves no temp folder in the app cache (DoD-21).
- [ ] Turning off the network mid-download fails the job with a network error within about 60s (DoD-22).
- [ ] Settings shows the yt-dlp version, and Update yt-dlp updates it (DoD-23).

Everywhere:

- [ ] A link from another site yt-dlp supports (Vimeo, Dailymotion) downloads.
- [ ] The file is named after the video title, with spaces and case kept, and `:` `|` `/` `?` shown as look-alikes (D-39).
- [ ] Downloading the same video twice keeps both files, the second as ` (2)`, and never replaces a file.
- [ ] Windows: a Cyrillic or Arabic title is named correctly.

## v0.4 checks

docs/spec-v0.4.md and docs/spec-v0.4-share.md sections DoD, on top of the checks above.

Android, with the release APK, on the Android 12 device and at the latest API:

- [ ] A 1GB download completes with the screen off and the app in the background, and swiping Ftube from recents doesn't stop it (DoD-25, DoD-26).
- [ ] The notification shows the count and progress; Cancel all cancels every job; the result notification counts completed and failed jobs; nothing stays ongoing after the last job (DoD-27, DoD-29).
- [ ] With notifications denied, downloads still finish in the background (DoD-28).
- [ ] Pause all leaves a swipeable paused notification; Resume all, from it or the app, continues from the partial file and the file plays; the queue pauses, resumes and cancels a single job (DoD-43 to DoD-45, also on desktop).
- [ ] Sharing a link from YouTube and from Chrome lists Ftube and opens the popup at once over the sharing app, both cold and warm (DoD-31, DoD-42).
- [ ] Download in the popup closes it with a "Download started" toast and the job finishes; opening Ftube shows the same tab and state, with no second task in recents (DoD-32, DoD-33).
- [ ] Without All files access the popup offers Open Ftube; text without a link shows "No link found" (DoD-34).
- [ ] The popup shows only the chips the video has, and M4A saves a `.m4a` (DoD-46). A share right after app start shows the chips without waiting for the yt-dlp update (DoD-47).

## v0.5 checks

docs/spec-v0.5.md section DoD, on top of the checks above.

On desktop and on Android with the release APK:

- [ ] A YouTube playlist link shows its videos quickly, and downloading 10 of them as MP3 gives 10 files named by title (DoD-36).
- [ ] A `watch?v=…&list=…` link opens the video, and "Show playlist" opens the list (DoD-37).
- [ ] A channel link shows its tabs; Videos lists the newest 200 with "Showing the first 200"; going back (row or Android back) shows the tabs again (DoD-38, DoD-52).
- [ ] Private and deleted entries are greyed out and never queued; "Cancel all queued" cancels only queued jobs (DoD-39).
- [ ] Single-video links behave as in v0.4 (DoD-40).
- [ ] Sharing a playlist link shows the playlist message, and "Open in Ftube" shows its videos (DoD-48, DoD-49).
- [ ] Tapping a playlist's Download twice queues each video once; active rows show their status (DoD-50).
- [ ] Show/Hide videos toggles the list (DoD-51); "Clear all" empties the queue after confirmation and keeps finished files (DoD-53).

## After the tag

- [ ] The `Release` workflow is green. Read the `Smoke download` step on each OS; it may only warn when YouTube blocks the runner.
- [ ] The release has the macOS `.zip`, Windows `.zip`, Linux `.tar.gz` and three Android APKs (`-arm64-v8a`, `-armeabi-v7a`, `-x86_64`, about 39-47MB each since v0.3), and the job summaries show their sizes. The run also has an `android-symbols-*` artifact; download it before it expires (90 days) and keep it to read obfuscated crash traces with `flutter symbolize`. Note the desktop size cost of the unused FFmpegKit libraries (R-5).
- [ ] Each archive contains `LICENSE` and `THIRD_PARTY_NOTICES.md`.
