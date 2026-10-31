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

## License

[GPL-3.0](LICENSE)
