# Ftube - Specification

## Summary

- Ftube is a cross-platform Flutter port of `ftube.sh` from `vasile-novatchii/Linux-Features`. It fetches media info, downloads in any quality, extracts audio, converts media, and manages the downloaded files.
- Targets: macOS, Windows, Linux and Android. iOS and F-Droid are out of scope, and distribution is GitHub Releases only.
- The desktop installer contains only the app. On first launch it downloads `yt-dlp`, `ffmpeg`/`ffprobe` and `deno` for the host OS and CPU, verifies them and keeps them in the app support folder, so the user installs nothing by hand.
- Android uses `youtube_explode_dart` for downloads and `ffmpeg_kit_flutter_new_audio` for conversion and for muxing high-quality video and audio streams.
- Both platforms sit behind one `MediaService` interface. The app follows MVVM as in the Flutter architecture guide: Views, ViewModels (Riverpod notifiers), Repositories and Services.
- Stack: latest stable Flutter (3.47.9), Riverpod 3, `gen-l10n` (EN default, RO), Material 3 with Light, Dark and System themes (System is the default), GPL-3.0, package ID `io.github.infvyr.ftube`. Minimum OS: Android 12 and macOS 12.0.
- Downloads go to `Downloads/Ftube` on every platform.
- Main risks: (1) YouTube changes break `youtube_explode_dart` on Android, (2) the first launch needs internet and a few hundred MB of downloads, and (3) Android needs the user to grant "All files access" for `Download/Ftube`.

## 1. Context

**What Ftube talks to on each platform**

```mermaid
flowchart TD
  user([User])
  subgraph app["Ftube (Flutter)"]
    ui["Views + ViewModels"]
    desk[DesktopMediaService]
    mob[AndroidMediaService]
  end
  subgraph bins["Downloaded on first launch - app support/bin"]
    ytdlp[[yt-dlp]]
    ffcli[["ffmpeg + ffprobe"]]
    deno[[deno]]
  end
  yte[[youtube_explode_dart]]
  ffkit[[ffmpeg_kit_flutter_new_audio]]
  sites[[Video sites<br/>YouTube, others]]
  gh[[GitHub Releases<br/>yt-dlp updates]]
  mirror[["ftube release binaries-rN<br/>mirrored binaries"]]
  fs[("Downloads/Ftube")]
  user --> ui
  ui --> desk
  ui --> mob
  desk -->|Process| ytdlp
  desk -->|Process| ffcli
  ytdlp -->|"--ffmpeg-location"| ffcli
  ytdlp -->|"--js-runtimes"| deno
  inst[BinaryInstaller] -->|"first launch"| mirror
  inst --> bins
  desk -->|"update yt-dlp"| gh
  mob --> yte
  mob -->|"convert, mux"| ffkit
  ytdlp --> sites
  yte -->|YouTube only| sites
  ytdlp --> fs
  ffcli --> fs
  mob --> fs
  classDef new fill:#d4f7d4,stroke:#2e7d32
  classDef ext fill:#e3e8ef,stroke:#5b6b82
  class ui,desk,mob,inst new
  class ytdlp,ffcli,deno,yte,ffkit,sites,gh,mirror ext
```

- Desktop supports any site `yt-dlp` supports. Android supports YouTube only.
- `yt-dlp` needs `ffmpeg` and `ffprobe` to merge formats and to extract audio with `-x`. It finds them through `--ffmpeg-location`, and Deno through `--js-runtimes`.

### Feature mapping from `ftube.sh`

| `ftube.sh` menu | Ftube | Desktop | Android |
|---|---|---|---|
| 0 Paste URL | URL field, paste button, clipboard URL detection | ✓ | ✓ |
| 1 List formats | Quality presets + "All formats" list | `yt-dlp -J` | `getManifest` |
| 2 Download format | Download the chosen preset or format, up to best quality | `yt-dlp -f` (merged by ffmpeg) | video-only + audio-only streams, muxed by ffmpeg_kit |
| 3 Extract MP3 | "Audio MP3" / "Audio OGG" presets | `yt-dlp -x` | audio stream, then ffmpeg_kit |
| 4 View files | Library screen | ✓ | ✓ |
| 5/6/7 Convert | "Convert to MP3/OGG" action on a library file | ffmpeg | ffmpeg_kit |
| 8 Open with player | "Open" (system default app) | ✓ | ✓ |
| 9 Exit | - | - | - |

## 2. Architecture (MVVM)

**Layers, following the Flutter architecture guide**

```mermaid
flowchart TD
  subgraph uiL["UI layer - lib/ui/"]
    hv[HomeView] --> hvm[HomeViewModel]
    qv[QueueView] --> qvm[QueueViewModel]
    lv[LibraryView] --> lvm[LibraryViewModel]
    sv[SettingsView] --> svm[SettingsViewModel]
  end
  subgraph dataL["Data layer - lib/data/"]
    dr[DownloadRepository]
    lr[LibraryRepository]
    sr[SettingsRepository]
    ms[MediaService]
    fss[FileSystemService]
    ps[PrefsService]
    bin[BinaryService]
    inst[BinaryInstaller]
  end
  subgraph impl["Platform implementations"]
    dms[DesktopMediaService]
    ams[AndroidMediaService]
    pr[ProcessRunner]
  end
  hvm --> dr
  hvm --> sr
  qvm --> dr
  lvm --> lr
  lvm --> dr
  svm --> sr
  svm --> bin
  svm --> inst
  dr --> ms
  dr --> fss
  lr --> fss
  lr --> ms
  sr --> ps
  dms -.implements.-> ms
  ams -.implements.-> ms
  dms --> pr
  dms --> bin
  bin --> pr
  inst --> pr
```

- **Views** are widgets with no business logic. Each View has exactly one ViewModel.
- **ViewModels** are Riverpod `Notifier`/`AsyncNotifier` classes. Each exposes an immutable UI state (`freezed`) and command methods.
- **Repositories** are the source of truth and never call each other.
  - `DownloadRepository` owns the job queue.
  - `LibraryRepository` lists, deletes and converts files.
  - `SettingsRepository` holds the settings.
- **Services** are stateless wrappers:
  - `MediaService` covers yt-dlp/ffmpeg or the Android libraries.
  - `FileSystemService` handles listing, deleting, reveal and open.
  - `PrefsService` wraps `shared_preferences`.
  - `BinaryService` locates the desktop binaries, reports their versions and updates yt-dlp.
  - `BinaryInstaller` (desktop) checks which binaries are missing or outdated against the catalog and downloads, verifies and unpacks them, with progress and cancel.
  - `StoragePermissionService` (Android) checks and requests storage access and resolves the public Downloads path.
- Domain models live in `lib/domain/models/`: `MediaInfo`, `MediaFormat`, `QualityPreset`, `DownloadJob`, `JobStatus`, `LibraryItem` and `AppSettings`.
- Providers are wired in `lib/config/providers.dart`. `mediaServiceProvider` chooses the implementation by platform, and tests override any provider with a fake.

**Service contract**

```mermaid
classDiagram
  class MediaService {
    <<interface>>
    +fetchInfo(String url) Future~MediaInfo~
    +download(DownloadRequest req) Stream~JobProgress~
    +convert(File src, AudioTarget target, File dst, String jobId) Stream~JobProgress~
    +cancel(String jobId) Future~void~
  }
  class DownloadRequest {
    +String jobId
    +String url
    +QualityPreset preset
    +String? formatId
    +Directory outDir
  }
  class QualityPreset {
    <<enum>>
    best
    p1080
    p720
    p480
    audioMp3
    audioOgg
    custom
  }
  class MediaInfo {
    +String url
    +String title
    +String? uploader
    +Duration? duration
    +String? thumbnailUrl
    +List~MediaFormat~ formats
  }
  class MediaFormat {
    +String id
    +String container
    +String? resolution
    +int? height
    +int? fps
    +int? bitrateKbps
    +int? sizeBytes
    +FormatKind kind
  }
  class JobProgress {
    +String jobId
    +JobPhase phase
    +double? fraction
    +int? downloadedBytes
    +int? totalBytes
    +double? speedBps
    +Duration? eta
    +String? outputPath
  }
  class JobPhase {
    <<enum>>
    downloadingVideo
    downloadingAudio
    merging
    converting
    finished
  }
  MediaService ..> DownloadRequest
  MediaService ..> MediaInfo
  MediaService ..> JobProgress
  DownloadRequest --> QualityPreset
  MediaInfo *-- MediaFormat
  JobProgress --> JobPhase
```

- Failures are typed `FtubeException` subclasses: `InvalidUrl`, `Unsupported`, `Network`, `BinaryMissing`, `ProcessFailed(exitCode, stderrTail)`, `ChecksumMismatch`, `StoragePermission` and `Cancelled`. ViewModels map each to a localized message.
- Desktop format selection: `best` = `bv*+ba/b`, `p1080` = `bv*[height<=1080]+ba/b[height<=1080]`, and so on for the other heights. `custom` uses the chosen `formatId`.
- Android format selection: the best video-only stream at or below the preset height, plus the best audio-only stream in a compatible container (mp4+m4a or webm+webm), muxed with `-c copy`.

## 3. Main flows

**Desktop first launch: installing the binaries (D-18)**

```mermaid
sequenceDiagram
  participant V as Setup screen
  participant I as BinaryInstaller (new)
  participant G as ftube release binaries-rN
  participant D as app support/bin
  V->>I: missing()
  I->>D: read installed.json, check files
  I-->>V: [ffmpeg, ffprobe, deno, yt-dlp]
  V->>I: install()
  loop each missing binary
    I->>G: GET name-os-arch.gz
    G-->>I: bytes, to name.gz.part
    I-->>V: InstallProgress(bytes, total)
    alt SHA-256 matches catalog
      I->>D: gunzip to name.tmp, rename, chmod 755, stamp
    else mismatch or network error
      I->>D: delete .part and .tmp
      I-->>V: ChecksumMismatch or Network
    end
  end
  I-->>V: done
```

**Desktop high-quality download (yt-dlp)**

```mermaid
sequenceDiagram
  participant V as HomeView
  participant VM as HomeViewModel
  participant R as DownloadRepository
  participant S as DesktopMediaService
  participant P as ProcessRunner
  V->>VM: fetch(url)
  VM->>S: fetchInfo(url)
  S->>P: "yt-dlp -J --no-playlist url"
  P-->>S: JSON stdout
  S-->>VM: MediaInfo
  V->>VM: download(preset)
  VM->>R: enqueue(DownloadRequest)
  R->>S: download(req)
  S->>P: "yt-dlp -f sel --ffmpeg-location bin --newline --progress-template ... -P Downloads/Ftube"
  loop stdout lines
    P-->>S: download / postprocess line
    S-->>R: JobProgress
  end
  alt exit 0
    R-->>R: status completed, outputPath
  else exit != 0
    R-->>R: status failed, ProcessFailed
  end
```

- The flags `--restrict-filenames`, `--ignore-config` and `--no-playlist` are always passed, matching `ftube.sh`.
- QueueView and LibraryView observe the same `DownloadRepository` stream.

**Android high-quality download**

```mermaid
sequenceDiagram
  participant R as DownloadRepository
  participant A as AndroidMediaService
  participant Y as youtube_explode_dart
  participant F as ffmpeg_kit
  R->>A: download(req p1080)
  A->>Y: getManifest(videoId)
  Y-->>A: streams
  A->>Y: get(videoOnly 1080p)
  Y-->>A: bytes to temp file (phase downloadingVideo)
  A->>Y: get(audioOnly best)
  Y-->>A: bytes to temp file (phase downloadingAudio)
  A->>F: "-i v -i a -c copy out.mp4" (phase merging)
  F-->>A: rc 0
  A-->>R: JobProgress finished, outputPath
```

- Temp files are deleted on success, failure and cancel.
- Progress across the phases is weighted: video 0-80%, audio 80-95%, merge 95-100%.

**Download job lifecycle**

```mermaid
stateDiagram-v2
  [*] --> queued: enqueue
  queued --> running: slot free
  running --> running: progress
  running --> completed
  running --> failed
  running --> cancelled: cancel
  queued --> cancelled: cancel
  failed --> queued: retry
  cancelled --> queued: retry
  completed --> [*]: clear
  failed --> [*]: remove
  cancelled --> [*]: remove
```

- Up to N jobs run at once, where N comes from Settings (1-3, default 2).
- The queue is held in memory. Jobs still running when the app quits are lost in v1.
- Library files are the persistent record of what was downloaded.

## 4. UI

**Navigation: NavigationBar on Android, NavigationRail on desktop**

```figure
┌────────────────────────────────────────────────────────────┐
│ Ftube                                                      │
├────────────────────────────────────────────────────────────┤
│ [ https://youtu.be/...                      ] [Paste] [Go] │
│ ┌──────┐ Song title                                        │
│ │thumb │ Channel · 03:42                                   │
│ └──────┘                                                   │
│ Quality: (Best) (1080p) (720p) (480p) (MP3) (OGG) [All ▾]  │
│                                          [ Download ]      │
├────────────────────────────────────────────────────────────┤
│ Queue (2)                                    [Clear done]  │
│ Song title · 1080p        ███████░░░  68%  4.2MB/s  0:09 ✗ │
│ Other video · MP3         merging...                     ✗ │
│ Broken link               failed: network          [Retry] │
├────────────────────────────────────────────────────────────┤
│        Home          Library          Settings             │
└────────────────────────────────────────────────────────────┘
```

**Actions per screen**

| Screen | Actions |
|---|---|
| Home | Paste URL, auto-detect a URL on the clipboard (with a prompt), fetch info with thumbnail/title/duration, choose a quality preset or a specific format, download |
| Queue (on Home; also a badge) | Live progress (percent, phase, size, speed, ETA), cancel, retry, remove, clear finished, open the finished file |
| Library | List files in `Downloads/Ftube` with type icon, size and date; search; filter (Video / Audio); sort (date / name / size); open; reveal in folder (desktop) or share (Android); convert to MP3/OGG; rename; delete one; multi-select delete; delete all. Every delete asks for confirmation |
| Settings | Theme (System default / Light / Dark), language (English default / Română), download folder (default `Downloads/Ftube`; changeable with a reset on desktop, fixed on Android, see D-9), default quality preset, concurrent downloads (1-3), yt-dlp version + "Update yt-dlp" (desktop), ffmpeg version, About (app version, GPL-3.0, third-party licenses for yt-dlp, FFmpeg and packages) |

- Android first run: a permission screen explains the need for "All files access" and opens the system setting. Settings shows the access status, with a button to grant it.
- Snackbars confirm actions. Delete actions offer Undo for 5 seconds before the file is removed.
- Empty states: no URL yet, empty queue, empty library.

## 5. Decisions

- D-1: Desktop needs `yt-dlp` standalone binaries (`yt-dlp_macos`, `yt-dlp.exe`, `yt-dlp_linux`), static `ffmpeg`/`ffprobe` and `deno`. They are not in the installer: `BinaryInstaller` downloads them on first launch. yt-dlp gets Deno through `--js-runtimes deno:<path>` for full YouTube support. Deno is optional at runtime: without it yt-dlp warns and some formats may be missing.
- D-2: Upstream versions are pinned by URL and SHA-256 in `tool/binaries.yaml`:
  - yt-dlp 2026.10.26: GitHub releases of yt-dlp.
  - FFmpeg 9.0.2: Martin Riedl static builds (macOS arm64 + x86_64), GyanD essentials (Windows), BtbN GPL (Linux).
  - Deno 2.9.8: GitHub releases of Deno.
- D-17: The app downloads from a mirror, not from upstream. `tool/package_binaries.dart` turns the upstream files into one gzip per binary, OS and CPU (`<binary>-<os>-<arch>.gz`) and writes `assets/binaries/catalog.json` with each file's URL, SHA-256 and size. Pushing a tag `binaries-rN` runs `.github/workflows/release_binaries.yml`, which rebuilds the files, checks that they match the committed catalog byte for byte, and publishes them as a pre-release of the `ftube` repo. Old app versions keep working because each catalog points at its own immutable release.
- D-18: First launch on desktop:
  - `BinaryInstaller` compares `<app support>/bin/installed.json` with the catalog entries for the host OS and CPU (`Abi.current()`). A binary is installed when its file exists and the stamp has the catalog's SHA-256.
  - Missing binaries are downloaded one by one to `<name>.gz.part`, verified against the SHA-256 before anything is unpacked, then gunzipped to `<name>.tmp`, renamed into place and made executable. The stamp is updated after each binary.
  - Progress is reported in bytes over the total size of what is missing. Cancel, network errors and checksum errors leave no partial files.
  - The setup screen (P5) blocks downloads until everything is installed, with Retry on failure.
  - Supported CPUs: macOS arm64 and x86_64, Windows x86_64, Linux x86_64. Others get `Unsupported`.
- D-3: `BinaryService` runs the binaries from `<app support>/bin`. During development the `FTUBE_BIN_DIR` environment variable points it at `build/binaries/<os>` from `tool/fetch_binaries.dart` instead.
- D-4: "Update yt-dlp" runs `yt-dlp -U` on the installed copy in `<app support>/bin`. The installer keeps an updated yt-dlp as long as the catalog entry does not change; a new catalog entry in a newer app version replaces it.
- D-5: Android uses `youtube_explode_dart` + `ffmpeg_kit_flutter_new_audio`. High quality comes from muxing a video-only and an audio-only stream with `-c copy`.
- D-6: The architecture is MVVM as in the Flutter guide, with Riverpod 3 notifiers as ViewModels, `riverpod_generator` and `freezed` for state.
- D-7: Theme uses `ThemeMode.system` by default, with a user override for Light or Dark. Material 3 with a seeded `ColorScheme`.
- D-8: Localization uses `gen-l10n` with ARB files: `app_en.arb` is the template and `app_ro.arb` the translation. English is the default and the fallback.
- D-9: Downloads go to `Downloads/Ftube` by default. Desktop uses `getDownloadsDirectory()` + `Ftube`. Android uses the public `Download/Ftube` folder, read and written with plain `dart:io` file paths (see D-13).
  - The folder can be changed only on desktop. Android keeps `Download/Ftube`, because the system folder picker returns content URIs, not file paths.
- D-13: Android storage access:
  - Request `MANAGE_EXTERNAL_STORAGE` ("All files access") through `permission_handler`. This gives full read, write and delete in `Download/Ftube`, including files left from a previous install or added by other apps. Google Play restricts this permission, but Ftube is not on Play.
  - Since `minSdk` is 31 (D-15), there is no legacy storage branch.
  - Resolve the public Downloads path through a small `MethodChannel` (`Environment.getExternalStoragePublicDirectory(DIRECTORY_DOWNLOADS)`). New files are announced to the gallery and media apps with `MediaScannerConnection.scanFile`.
  - A first-run permission screen explains why access is needed. If access is denied, downloads are blocked with a "Grant access" button.
- D-15: Minimum OS versions:
  - Android 12 (`minSdk 31`). `compileSdk` is 37 because `permission_handler_android` 14 requires it; `targetSdk` stays at Flutter's default.
  - macOS 12.0, Flutter 3.47.9's template default (`MACOSX_DEPLOYMENT_TARGET`).
  - Windows and Linux use Flutter's defaults.
- D-14: macOS ships one universal `.app` for arm64 and x86_64. The binaries are downloaded for the host CPU only (`yt-dlp_macos` is already universal and serves both). `tool/fetch_binaries.dart` still builds universal binaries with `lipo` for development.
- D-10: "Open with player" becomes "open with the system default app".
- D-11: The macOS App Sandbox is off and the network client entitlement is on, so the app can download and run its binaries.
- D-16: Desktop progress comes from yt-dlp `--progress-template` lines on stdout (`FTUBE|...`), postprocessor lines on stderr (`FTUBE_PP|...`) and `--print after_move:FTUBE_FILE|<path>`. Partial files go to a per-job temp folder (`-P temp:`), deleted when the job ends. Local conversion reads `ffmpeg -progress pipe:1`. The `custom` preset passes `formatId` to `-f` as is, so it may be a full selector such as `399+ba`.
- D-17: `build_runner` is held at 2.16.x, because `riverpod_generator` 4.0.9 does not resolve with build_runner 2.17.1.
- D-12: Lints use `flutter_lints` plus strict-casts, strict-inference and strict-raw-types.

## 6. Testing

| Level | Covers | Tools |
|---|---|---|
| Unit | yt-dlp JSON and progress parsers, ffmpeg progress parser, format-selector builder, Android stream picker, phase weighting, exception mapping | `test`, fixtures in `test/fixtures/` |
| Unit | `DesktopMediaService` and `BinaryService` with a fake `ProcessRunner` (success, non-zero exit, missing binary, cancel, update) | `mocktail` |
| Unit | `BinaryInstaller` against a local `HttpServer`: install, skip installed, reinstall on catalog change, redirect, 404, offline, checksum mismatch, cancel | `dart:io` |
| Unit | Repositories: queue concurrency, retry, cancel, library list/sort/filter, delete one/many/all, settings persistence | fakes for the services |
| ViewModel | State transitions per ViewModel, including the job lifecycle diagram | `ProviderContainer` + overrides |
| Widget | Every View in EN and RO and in Light and Dark; empty, loading and error states; delete confirmation and Undo | `flutter_test` |
| l10n | Every key in `app_en.arb` exists in `app_ro.arb` | unit test |
| Unit | `StoragePermissionService`: granted, denied and permanently denied, with the platform channel mocked | `TestDefaultBinaryMessenger` |
| Integration | Paste → download → library → delete with a fake service, on desktop and an Android emulator | `integration_test` |
| Manual | Android `Download/Ftube` on API 31 and on the latest API: grant and deny access, reinstall, then delete old files | `docs/release.md` checklist |
| Smoke | `tool/install_binaries.dart` installs from the real catalog on each OS and runs every binary's version command | `binaries.yml` CI workflow |
| Smoke | One short download per OS with the installed binaries | CI release job + `docs/release.md` checklist |

- Coverage gate: at least 85% line coverage for `lib/data/` and `lib/ui/**/view_model*`, enforced in CI.
- CI (GitHub Actions) runs analyze, format check and tests with coverage on every push and PR. Tags `v*` build macOS, Windows, Linux and Android and run the smoke test.

## 7. Phases (one clean commit per phase)

```mermaid
flowchart LR
  p0["P0 Spec"] --> p1["P1 Scaffold<br/>create, LICENSE, lints, CI"]
  p1 --> p2["P2 Domain + services API<br/>models, exceptions, MediaService"]
  p2 --> p3["P3 Desktop<br/>binaries tooling, BinaryService,<br/>DesktopMediaService"]
  p2 --> p4["P4 Android<br/>AndroidMediaService, HQ mux,<br/>storage"]
  p1 --> p5["P5 App shell<br/>theme, l10n, Settings MVVM"]
  p3 --> p3b["P3b First-run install<br/>catalog, mirror release,<br/>BinaryInstaller"]
  p3b --> p6["P6 Repositories<br/>queue, library"]
  p4 --> p6
  p6 --> p7["P7 Home + Queue MVVM"]
  p5 --> p7
  p6 --> p8["P8 Library MVVM"]
  p5 --> p8
  p7 --> p9["P9 Release<br/>build matrix, README, v0.1.0"]
  p8 --> p9
```

**Definition of Done**

- DoD-1: Every row of the feature mapping table works on macOS, Windows, Linux and Android, including high-quality downloads on Android.
- DoD-2: A fresh desktop install downloads its binaries on first launch, then downloads and converts without the user installing yt-dlp, ffmpeg or Deno.
- DoD-3: Analyze and format are clean, all tests pass, and the coverage gate is met.
- DoD-4: The theme follows the OS on a fresh install, and the user can override it.
- DoD-5: The app is in English on a fresh install, and every string exists in both EN and RO.
- DoD-6: Files land in `Downloads/Ftube` by default, and single, multi-select and delete-all all work with confirmation. On Android this also covers files from a previous install or from other apps.
- DoD-10: macOS ships as one universal `.app` (`lipo -archs` reports `x86_64 arm64` for the app binary), and first launch installs working binaries on both Apple silicon and Intel.
- DoD-7: The queue shows live progress, cancel, retry and remove.
- DoD-8: A tag `v*` publishes macOS (.zip), Windows (.zip), Linux (.tar.gz) and Android (.apk) artifacts to a GitHub Release.
- DoD-9: The repo has a GPL-3.0 `LICENSE` and a third-party notices file. The README has install steps per OS, including the macOS quarantine note.

## 8. Constraints and risks

- R-1: The binaries are large, so first launch downloads a few hundred MB and needs internet. Accepted in exchange for a small installer. Without internet, the setup screen offers Retry and nothing else works on desktop.
- R-2: Resolved in P3/P3b: `yt-dlp_macos` is already universal, and the other binaries are downloaded per CPU, so nothing is doubled.
- R-3: "All files access" is a broad permission and users must grant it manually in system settings. If they refuse, Android downloads cannot run (D-13). Some OEM ROMs may behave differently, so P4 tests on an emulator at API 31 and on the latest API.
- R-4: `youtube_explode_dart` breaks when YouTube changes, and some clients need a JS challenge solver. Android downloads may fail until the package is updated. Its default Android client may refuse a second download from the same manifest, so `AndroidMediaService` fetches a fresh manifest before the audio stream.
- R-5: Confirmed in P4: `ffmpeg_kit_flutter_new_audio` 2.5.7 declares macOS, Windows and Linux. Its Windows and Linux CMake files download the FFmpegKit audio bundle at build time, and on macOS its podspec vendors `ffmpegkit.framework`. pubspec cannot limit a plugin to one platform, so desktop builds carry these libraries unused. The size gets measured in P9 on the CI build matrix (this machine has no Xcode). If it is too large, move the Android media code into a local Android-only plugin.
- R-6: Android has no background downloads in v1. Downloads stop if the OS kills the app, and a foreground-service notification is planned for v2.
- R-7: Unsigned macOS and Windows builds trigger Gatekeeper and SmartScreen warnings. Document the `xattr` fix in the README. Binaries the app downloads itself are expected not to get the quarantine flag; verify on macOS 12 and the latest macOS in P9.
- R-8: The mirrored ffmpeg and the PyInstaller yt-dlp binaries contain GPL code. Ftube is GPL-3.0, so this is compatible, but the notices and source links must ship with each release.
- R-9: The ffmpeg builds target macOS 12.0 and yt-dlp 11.0 (resolved in P3). ffmpeg_kit needs Android `minSdk 24` and macOS 10.15, both below Ftube's minimums (resolved in P4).
- R-11: Mirroring makes the `ftube` repo responsible for hosting GPL binaries. Each `binaries-rN` release notes link to the upstream sources (R-8).
- R-10: On macOS and Linux, cancelling a download kills yt-dlp, but an ffmpeg child it started (merge or extract) may keep running until it finishes. Its output lands in the job temp folder, which is deleted.

## 9. Non-goals (v1)

- iOS, F-Droid, app store releases.
- Playlist and channel downloads.
- Background downloads on Android, or persisting the queue across restarts.
- A built-in media player.
