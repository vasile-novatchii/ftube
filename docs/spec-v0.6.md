# Ftube Downloader v0.6

Builds on release v0.5: [spec-v0.5.md](spec-v0.5.md). Decision, DoD and risk IDs continue its numbering. Each v0.6 feature has its own numbered part below; more features will be added as further parts.

## Summary

- **Part A - update notice:** Ftube checks GitHub Releases for a newer version and tells the user. **Download** opens that version's release page in the browser, and the user installs it by hand as today (README). This works the same way on macOS, Windows, Linux and Android. Ftube is not in the Play Store and doesn't install updates itself.
- **How:** an `AppUpdateService` reads `GET /repos/vasile-novatchii/ftube/releases/latest` with the existing `HttpClient`. An `AppUpdateRepository` compares the tag with `PackageInfo.version`, limits checks to one a day and remembers a skipped version. Home shows the existing `_Banner` with What's new (release notes) / Download / Later / Skip, and Settings gets "Check for updates". Android also posts one system notification per new version.
- **Release side:** the `Release` workflow fails instead of signing the APK with a throwaway debug key, so an APK from the release page always installs over the old one.
- **Main risks:** the unauthenticated GitHub API limit of 60 requests per hour per IP (R-36), and opening a URL from the desktop without a new package (R-37).
- **Part B - changelog:** a hand-written `CHANGELOG.md` at the repo root is bundled as an asset. Tapping Settings > App version opens it, rendered as Markdown with `flutter_markdown_plus`. The `Release` workflow takes that version's section as the GitHub release notes, so Part A's "What's new" shows the same text.
- **Part C - supported formats:** Settings gets "Supported formats", a screen built from the app's own enums: video containers, audio formats, quality presets, and a link to yt-dlp's list of supported sites.
- **Part D - privacy note:** the README gets a short "Privacy" section. There is no Terms page (GPLv3 sections 15-16 already disclaim warranty and liability) and no in-app privacy page.

## A1. What changes

**Which parts change**

```mermaid
flowchart TD
  subgraph ui["Views + ViewModels"]
    home["HomeView<br/>update _Banner"]
    settings["SettingsView<br/>Check for updates"]
    vm["AppUpdateViewModel (new)"]
  end
  subgraph data["Data"]
    repo["AppUpdateRepository (new)<br/>compare, daily limit, skip"]
    svc["AppUpdateService (new)<br/>GitHub latest release"]
    prefs["PrefsService"]
    fs["FileSystemService.openUrl (new)"]
    notif["AndroidUpdateNotifier (new)"]
  end
  gh[["GitHub REST API"]]
  browser[["Browser"]]
  kt["MainActivity.kt / DownloadsChannel.kt<br/>openUrl, update notification"]
  home --> vm
  settings --> vm
  vm --> repo --> svc --> gh
  repo --> prefs
  vm --> fs --> browser
  vm --> notif --> kt
  fs -->|Android| kt
  classDef new fill:#d4f7d4,stroke:#2e7d32
  classDef changed fill:#fff3c4,stroke:#b38600
  classDef ext fill:#e3e8ef,stroke:#5b6b82
  class vm,repo,svc,notif new
  class home,settings,fs,kt changed
  class gh,browser ext
```

- `appVersionProvider` (`lib/config/providers.dart`) already reads `PackageInfo.version`; the repository reuses it.
- The name `AppUpdate` keeps it apart from the yt-dlp `UpdateStatus` in Settings.

## A2. Data model

**What a check returns**

```mermaid
classDiagram
  class AppRelease {
    +String version
    +String tag
    +Uri pageUrl
    +DateTime? publishedAt
    +String notes
  }
  class UpdateCheck {
    <<sealed>>
  }
  class UpToDate {
    +String current
  }
  class UpdateAvailable {
    +String current
    +AppRelease release
  }
  class CheckFailed {
    +String reason
  }
  UpdateCheck <|-- UpToDate
  UpdateCheck <|-- UpdateAvailable
  UpdateCheck <|-- CheckFailed
  UpdateAvailable *-- AppRelease
```

| JSON field (`releases/latest`) | `AppRelease` |
|---|---|
| `tag_name` (`v0.6.0`) | `tag`; `version` = tag without the leading `v` |
| `html_url` | `pageUrl` (`https://github.com/vasile-novatchii/ftube/releases/tag/v0.6.0`) |
| `published_at` | `publishedAt` |
| `body` (Markdown) | `notes`, as plain text (D-97) |

| Pref key | Value |
|---|---|
| `appUpdate.lastCheck` | epoch ms of the last successful check |
| `appUpdate.skipped` | version the user skipped, e.g. `0.6.0` |
| `appUpdate.notified` | version Android already posted a notification for |

## A3. Flows

**The check at startup**

```mermaid
sequenceDiagram
  participant S as AppShell
  participant V as AppUpdateViewModel
  participant R as AppUpdateRepository
  participant G as AppUpdateService
  participant N as AndroidUpdateNotifier
  S->>V: build (once per launch)
  V->>R: check(force: false)
  alt last check under 24h ago
    R-->>V: no result (no request)
  else
    R->>G: latestRelease()
    G-->>R: AppRelease or error
    R-->>V: UpdateCheck
  end
  opt UpdateAvailable, not skipped
    V-->>S: Home shows the update banner
    V->>N: notify(release) once per version (Android)
  end
```

**Whether the banner shows**

```mermaid
flowchart TD
  r["UpdateCheck"] --> a{"UpdateAvailable?"}
  a -->|"UpToDate / CheckFailed"| hide["no banner<br/>(startup check stays silent)"]
  a -->|yes| s{"release.version == skipped?"}
  s -->|yes| hide
  s -->|no| l{"Later tapped this launch?"}
  l -->|yes| hide
  l -->|no| show["banner: Ftube X is available<br/>What's new / Download / Later / Skip this version"]
  show -->|"What's new"| notes["release notes sheet<br/>with Download"]
  notes -->|Download| open
  show -->|Download| open["openUrl(pageUrl)<br/>banner stays"]
  show -->|Later| hide
  show -->|Skip| skip["save skipped = version"] --> hide
```

## A4. Decisions

- D-87: no in-app install - Download opens the release page, and the user picks the file and installs it as the README says. Self-install (Android `PackageInstaller`, a desktop helper that replaces the app) is a later phase, see the non-goals.
- D-88: the GitHub REST API `releases/latest` endpoint, no login - it returns the newest release that is not a draft or prerelease, so neither a prerelease tag nor the binaries pre-release in `assets/binaries/catalog.json` ever triggers the notice. Requests send `Accept: application/vnd.github+json` and `User-Agent: Ftube/<version>`, with a 10s timeout.
- D-89: one automatic check per 24h, run in the background after startup so it never delays the UI. `lastCheck` is saved only after a successful check, so an offline start tries again on the next launch.
- D-90: versions compare as `major.minor.patch` integers. A tag that doesn't parse, or a pubspec build suffix (`+5`), is ignored; an unparseable tag counts as "no update".
- D-91: the notice is the existing Home `_Banner`, not a dialog - it doesn't block a paste or a download in progress. Later hides it until the next launch; Skip hides it until a newer version appears.
- D-92: Settings shows "Check for updates" below App version. It ignores the 24h limit and the skipped version and shows its result in the tile subtitle: "Up to date", "Version X is available" with Download, or "Couldn't check for updates".
- D-93: Android posts one notification per new version on a new `app_update` channel, from the startup check only; the manual Settings check never posts one, since the user is already looking at the result. Tapping it opens the release page. Without the notification permission it is skipped silently; the banner still shows. There is no background check while Ftube is closed.
- D-94: `FileSystemService.openUrl(Uri)` opens the page: `open` on macOS, `rundll32 url.dll,FileProtocolHandler` on Windows (no `cmd /c start`, so the URL is never parsed by a shell), `xdg-open` on Linux, and a new `openUrl` method on the `io.github.infvyr.ftube/files` channel (`ACTION_VIEW`) on Android. No new package (`url_launcher`) is added.
- D-95: the `Release` workflow fails when `FTUBE_KEYSTORE_BASE64` is missing, instead of signing with a throwaway debug key. An APK signed with another key can't install over the old one, so a debug-signed release would break updating for every Android user.
- D-96: the README gets an "Updating" section per OS: Android installs over the old app and keeps its data; macOS replaces `Ftube.app` and repeats the `xattr` step; Windows and Linux replace the unpacked folder.
- D-97: release notes - the banner and the Settings result get "What's new", which opens a scrollable sheet with the version, date, notes and Download. The release `body` is Markdown and is rendered with the `MarkdownView` from Part B (D-99), so it reuses that package instead of a plain-text reducer. An empty body shows "No release notes".

## A5. Testing

| Level | Covers | Tools |
|---|---|---|
| Unit | `AppUpdateService`: parses `tag_name` / `html_url` / `published_at`; 403, 404, 429, timeout and bad JSON become `CheckFailed` | fake `HttpClient`, JSON fixture from a real release |
| Unit | version compare (D-90): `0.10.0 > 0.9.9`, equal, `v` prefix, build suffix, unparseable tag | `test` |
| Unit | `AppUpdateRepository`: 24h limit, force bypass, `lastCheck` only on success, skipped version, notify once per version | fake service, in-memory `PrefsService` |
| Widget | Home banner: Download / Later / Skip, hidden when skipped; Settings tile states | `flutter_test`, `ProviderContainer` overrides |
| Manual | an older build against the live `latest` release on each OS: banner, Download opens the page, Android notification, Settings check offline | desktop and Android release builds |

## A6. Definition of Done

- DoD-54: An older build starts, and within a few seconds Home shows "Ftube X is available"; Download opens the release page of version X in the default browser on macOS, Windows, Linux and Android.
- DoD-55: Later hides the banner until the next launch; Skip hides it until a newer version is published.
- DoD-56: A second launch within 24h sends no request; Settings' "Check for updates" always sends one and shows its result, including "Couldn't check for updates" offline.
- DoD-57: On Android, a new version posts one notification; tapping it opens the release page. A second launch, or a manual Settings check, posts no second notification.
- DoD-61: "What's new" in the banner and in Settings shows the release notes of version X as rendered Markdown, without raw Markdown markers.
- DoD-58: Offline or rate-limited starts show nothing and log the error.
- DoD-59: The `Release` workflow fails without the keystore secret, and the README has the "Updating" steps.
- DoD-60: DoD-3 still holds: analyze and format are clean, all tests pass and the coverage gate is met. New strings exist in every ARB file (en, ar, de, es, ro, ru).

## A7. Risks

- R-36: GitHub allows 60 unauthenticated requests per hour per IP. Shared IPs (offices, CGNAT on mobile) may hit it; the 24h limit keeps Ftube's share tiny, and a 403/429 is a silent `CheckFailed` (DoD-58).
- R-37: opening a URL on Windows without `url_launcher` - `rundll32 url.dll,FileProtocolHandler` is the plan; verify it on Windows 10 and 11, and fall back to `url_launcher` if it fails.
- R-38: a release published before all its assets are uploaded would point users to a page with missing files. The `publish` job creates the release only after every build finishes, so this holds as long as releases are not created by hand.
- R-39: if the repo is renamed or made private, every check fails silently. The repo path is one constant in `AppUpdateService`.

## A8. Open questions

- None open for Part A.

## A9. Non-goals (v0.6 update notice)

- Downloading or installing the update inside Ftube (Android `PackageInstaller`, desktop self-replace), and silent updates.
- Checking for updates while Ftube is closed (WorkManager, launch agents).
- Prerelease or beta channels.

## B1. Changelog - what changes

**Where the changelog text goes**

```mermaid
flowchart LR
  md["CHANGELOG.md (new)<br/>repo root, hand-written"]
  asset["Flutter asset"]
  wf["Release workflow<br/>extract ## X.Y.Z section"]
  gh[["GitHub release body"]]
  tile["Settings > App version<br/>tap (changed)"]
  page["ChangelogView (new)"]
  mv["MarkdownView (new)<br/>flutter_markdown_plus"]
  sheet["Part A What's new sheet"]
  md --> asset --> page --> mv
  tile --> page
  md --> wf --> gh --> sheet --> mv
  classDef new fill:#d4f7d4,stroke:#2e7d32
  classDef changed fill:#fff3c4,stroke:#b38600
  classDef ext fill:#e3e8ef,stroke:#5b6b82
  class md,page,mv new
  class tile,wf,sheet changed
  class gh ext
```

**CHANGELOG.md format**

```markdown
# Changelog

## 0.6.0 - 2026-11-20

### Added
- Ftube tells you when a new version is out.

### Fixed
- ...
```

- One `## X.Y.Z - YYYY-MM-DD` heading per release, newest first, with `Added` / `Changed` / `Fixed` subsections as needed. Entries are written for users, not copied from commit messages.
- Backfilled for 0.1.0 to 0.5.0 from the tags and `docs/spec*.md`.

## B2. Decisions

- D-98: the changelog is a bundled asset, not fetched from GitHub - it works offline, costs no API requests (R-36), and always matches the installed build. `pubspec.yaml` lists `CHANGELOG.md` under `flutter.assets`.
- D-99: `flutter_markdown_plus` renders Markdown. It is the official replacement for the discontinued `flutter_markdown`. A shared `MarkdownView(data)` widget wraps it: `MarkdownStyleSheet.fromTheme`, selectable text, and links opened with `FileSystemService.openUrl` (D-94). Images are not loaded. The Part A release notes sheet (D-97) uses the same widget.
- D-100: Settings > App version gets a chevron and opens `ChangelogView` (title "Changelog", the whole file, scrollable). The tile keeps showing the version as its subtitle. The changelog text is English only; the page title and tile strings are localized.
- D-101: the `Release` workflow takes the `## X.Y.Z` section for the tag's version from `CHANGELOG.md` and puts it first in `notes.md`, ahead of the existing install text. It fails when that section is missing or empty, so a release can't ship without a changelog entry. `--generate-notes` stays for the compare link.
- D-102: a unit test reads the `pubspec.yaml` version and checks that `CHANGELOG.md` has a non-empty section for it, so the release commit's version bump fails CI until the entry is written.

## B3. Testing

| Level | Covers | Tools |
|---|---|---|
| Unit | `CHANGELOG.md` has a section for the pubspec version (D-102); the section extraction the workflow uses returns the right lines and nothing for a missing version | `test`, `yaml` |
| Widget | App version tile opens `ChangelogView`; `MarkdownView` renders headings and lists, and a link tap calls `openUrl` | `flutter_test`, fake `FileSystemService` |
| Manual | a tag without a changelog section fails `Release`; the release page and "What's new" show the section | GitHub Actions |

## B4. Definition of Done

- DoD-62: Tapping Settings > App version opens the changelog, newest version first, rendered as Markdown, offline too. Links in it open in the browser.
- DoD-63: `CHANGELOG.md` covers 0.1.0 to the current version, and CI fails when the pubspec version has no entry.
- DoD-64: The GitHub release for v0.6.0 starts with its changelog section, and the `Release` workflow fails on a tag without one.

## B5. Risks

- R-40: `flutter_markdown_plus` is a third-party package with Flutter-team origins; if it stalls, `MarkdownView` is the one place to swap it (for example for `markdown_widget`). Its license goes into `THIRD_PARTY_NOTICES.md` if needed and shows in the Flutter license page automatically.

## C1. Supported formats - what changes

- Settings > Downloads gets a "Supported formats" tile that opens `SupportedFormatsView`. The screen is built from the code, not a text file, so it can't drift from what the app actually does:

| Section | Content | Source |
|---|---|---|
| Video | MP4, WebM or MKV; the container is picked from the streams (MP4 video + M4A audio gives MP4, WebM + WebM gives WebM, anything else MKV) | `AndroidMediaService.muxExtension` / yt-dlp merger (D-35) |
| Audio | MP3 (converted), M4A (original stream, no conversion), OGG (converted) | `QualityPreset`, `AudioTarget` |
| Quality | Best, 1080p, 720p, 480p, 360p; "All formats" lists every stream the video offers | `QualityPreset` |
| Sites | YouTube (videos, playlists, channels); other sites via yt-dlp, with a link to its supported sites list | constant URL |

## C2. Decisions

- D-103: the lists come from `QualityPreset` and `AudioTarget`, and the labels from the same l10n strings Home uses, so a new preset shows up without editing this screen.
- D-104: the sites link opens `https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md` with `openUrl` (D-94). Ftube is tested on YouTube only, so the screen says other sites "may work" rather than promising them.
- D-105: the screen is static - no network, no yt-dlp call.

## C3. Testing and Definition of Done

- Widget test: every `QualityPreset` except `custom` and every `AudioTarget` appears on the screen; the sites link calls `openUrl`.
- DoD-65: Settings > Supported formats lists the video containers, audio formats and quality presets above, in every UI language, and the sites link opens yt-dlp's list.

## D1. Privacy note

- D-106: the README gets a "Privacy" section: Ftube has no accounts, analytics or tracking; it contacts only GitHub (binaries on desktop, update checks from Part A) and the sites the user downloads from; settings and history stay on the device. No in-app page and no Terms page - the GPLv3 text (sections 15-16) covers warranty and liability, and Settings already shows the license.
- DoD-66: the README has the Privacy section, and it matches the network calls in the code (`grep https://` in `lib/`).

## Non-goals (Parts B-D)

- Fetching the changelog or release history from GitHub at runtime.
- Translating the changelog.
- A Terms of Service page or an in-app privacy page.
- Per-site format lists or testing sites other than YouTube.
