# Ftube

Download and convert media on macOS, Windows, Linux and Android.
A Flutter port of [`ftube.sh`](https://github.com/vasile-novatchii/Linux-Features/blob/master/ftube.sh).

> Status: early development. See [docs/spec.md](docs/spec.md) for the full specification and phase plan.

## Development

The Flutter version is pinned with [fvm](https://fvm.app) in `.fvmrc`.

```bash
fvm install
fvm flutter pub get
fvm dart run build_runner build -d   # freezed code, not committed
fvm flutter analyze
fvm flutter test
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

## License

[GPL-3.0](LICENSE)
