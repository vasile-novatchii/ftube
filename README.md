# Ftube Downloader

Download and convert media on macOS, Windows, Linux and Android.
A Flutter port of [`ftube.sh`](https://github.com/vasile-novatchii/Linux-Features/blob/master/ftube.sh).

> Status: v0.5.0: YouTube playlist and channel links show their videos on Home as a checklist, and the picked videos download as one job each; channel tabs open their playlists with a way back, and the queue gains Clear all. See [docs/spec.md](docs/spec.md), [docs/spec-v0.2.md](docs/spec-v0.2.md), [docs/spec-v0.3.md](docs/spec-v0.3.md), [docs/spec-v0.4.md](docs/spec-v0.4.md), [docs/spec-v0.4-share.md](docs/spec-v0.4-share.md) and [docs/spec-v0.5.md](docs/spec-v0.5.md).

## Install

Download the file for your system from the [latest release](https://github.com/vasile-novatchii/ftube/releases/latest).

| System | File | Needs |
|---|---|---|
| macOS (Apple silicon and Intel) | `Ftube-<version>-macos.zip` | macOS 12 or later |
| Windows | `Ftube-<version>-windows.zip` | Windows 10 or later, x64 |
| Linux | `Ftube-<version>-linux.tar.gz` | x64 with GTK 3 |
| Android | `Ftube-<version>-android-arm64-v8a.apk` (most phones), `-armeabi-v7a.apk` (older 32-bit), `-x86_64.apk` (emulators) | Android 12 or later |

On first launch the desktop app downloads yt-dlp, ffmpeg, ffprobe and Deno (a few hundred MB) into its app support folder, so it needs internet once. Downloads go to `Downloads/Ftube`.

### macOS

1. Unzip the file and move `Ftube.app` to `Applications`.
2. The app is not signed, so macOS says it "cannot be opened" or "is damaged". Remove the quarantine flag once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Ftube.app
   ```

   Or open it once with right-click > **Open**, or allow it under **System Settings > Privacy & Security > Open Anyway**.

### Windows

1. Unzip the file anywhere, for example to `%LOCALAPPDATA%\Programs\Ftube`.
2. Run `ftube.exe`. The app is not signed, so SmartScreen may show "Windows protected your PC". Click **More info > Run anyway**.

### Linux

```bash
mkdir -p ~/.local/opt && tar -xzf Ftube-*-linux.tar.gz -C ~/.local/opt
~/.local/opt/Ftube-*-linux/ftube
```

The app needs GTK 3 (`libgtk-3-0`), which most desktops already have.

### Android

1. Open the APK on the phone and allow installing from this source when asked.
2. On first launch, grant **All files access**. Ftube needs it to save to and manage `Download/Ftube`, including files from a previous install.

Updates install over the previous version as long as both APKs come from this repo's releases.

## Development

The Flutter version is pinned with [fvm](https://fvm.app) in `.fvmrc`.

```bash
fvm install
fvm flutter pub get
fvm dart run build_runner build -d   # freezed code, not committed
fvm flutter analyze
fvm flutter test --coverage
fvm dart run tool/coverage_gate.dart   # at least 85% for lib/data and view models
fvm flutter run -d macos   # or windows, linux, an Android device
```

### Desktop binaries

The desktop app needs yt-dlp, ffmpeg, ffprobe and Deno, but the installer does not contain them. On first launch the app downloads them for the host OS and CPU from a `binaries-rN` pre-release of this repo, checks their SHA-256 against `assets/binaries/catalog.json` and keeps them in the app support folder.

Upstream versions are pinned in `tool/binaries.yaml`. To publish new binaries:

```bash
fvm dart run tool/package_binaries.dart --release binaries-r2   # rewrites the catalog
git commit -am "chore: binaries-r2" && git push
git tag -s binaries-r2 -m binaries-r2 && git push origin binaries-r2
```

The `Release binaries` workflow rebuilds the files, checks them against the committed catalog, publishes them, and runs an install smoke test on every OS.

For development without the first-launch download, fetch the binaries locally and point the app at them:

```bash
fvm dart run tool/fetch_binaries.dart --smoke   # into build/binaries/<os>
FTUBE_BIN_DIR=$PWD/build/binaries/macos fvm flutter run -d macos
```

### Releasing

Follow [docs/release.md](docs/release.md), then push a tag `vX.Y.Z` that matches the `pubspec.yaml` version. The `Release` workflow checks the code, builds macOS (universal), Windows, Linux and Android, and publishes them to a GitHub Release.

## License

[GPL-3.0](LICENSE). Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
