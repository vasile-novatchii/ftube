# Third-party notices

Ftube is free software under the [GNU General Public License v3.0](LICENSE).
It builds on the components below. The full license text of every Flutter and
Dart package compiled into the app is shown in the app under
**Settings > Third-party licenses**.

## Compiled into the app

| Component | License | Source |
|---|---|---|
| Flutter engine and framework | BSD-3-Clause | https://github.com/flutter/flutter |
| youtubedl-android (Android downloads; runs yt-dlp) | GPL-3.0 | https://github.com/JunkFood02/youtubedl-android |
| Python 3 (bundled by youtubedl-android) | PSF-2.0 | https://www.python.org |
| QuickJS (bundled by youtubedl-android) | MIT | https://bellard.org/quickjs |
| yt-dlp (bundled by youtubedl-android and updated by the app) | Unlicense | https://github.com/yt-dlp/yt-dlp |
| ffmpeg_kit_flutter_new_audio and FFmpegKit audio libraries (Android conversion and muxing; also bundled, unused, on desktop) | LGPL-3.0 | https://github.com/sk3llo/ffmpeg_kit_flutter |
| Riverpod | MIT | https://github.com/rrousselGit/riverpod |
| freezed_annotation | MIT | https://github.com/rrousselGit/freezed |
| permission_handler | MIT | https://github.com/Baseflow/flutter-permission-handler |
| file_selector, path_provider, shared_preferences, package_info_plus, http, intl, path, crypto | BSD-3-Clause | https://github.com/flutter/packages, https://github.com/dart-lang |

## Downloaded by the desktop app on first launch

The desktop app does not contain these programs. On first launch it downloads
them from a `binaries-rN` pre-release of this repository, which mirrors the
unchanged upstream files (gzipped). Versions are pinned in
[tool/binaries.yaml](tool/binaries.yaml), and each release's notes link to the
upstream sources.

| Program | License | Source |
|---|---|---|
| yt-dlp | Unlicense; the PyInstaller builds include GPL-licensed parts | https://github.com/yt-dlp/yt-dlp |
| FFmpeg and ffprobe | GPL-3.0 builds by Martin Riedl (macOS), GyanD (Windows) and BtbN (Linux) | https://ffmpeg.org, https://ffmpeg.martin-riedl.de, https://github.com/GyanD/codexffmpeg, https://github.com/BtbN/FFmpeg-Builds |
| Deno | MIT | https://github.com/denoland/deno |

The corresponding source code of the GPL and LGPL components is available from
the projects linked above.
