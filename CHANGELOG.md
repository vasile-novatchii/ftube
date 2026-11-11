# Changelog

## 0.6.0 - 2026-11-11

### Added
- Ftube tells you when a new version is out: a banner on Home, a check in Settings and, on Android, a notification. "What's new" shows the release notes before you download.
- Tap Settings > App version to read this changelog.
- The README explains what Ftube connects to and what stays on your device.
- Settings > Supported formats lists the video and audio formats, the qualities and the sites Ftube can download from.

## 0.5.0 - 2026-11-10

### Added
- Paste a YouTube playlist or channel link to see its videos as a checklist on Home, then download the ones you pick.
- Channel links show their tabs, and you can go back to the channel from a playlist.
- The share popup on Android recognizes playlist and channel links.
- The queue has a Clear all button.

### Changed
- A video that is already in the queue can't be added again.

## 0.4.0 - 2026-11-10

### Added
- Downloads keep running in the background on Android, with a progress notification and a Cancel all button.
- Share a link from another Android app to download it from a popup, without opening Ftube.
- Pause and resume downloads.

### Changed
- The share popup only offers the formats the video has.

### Fixed
- The keyboard on Android closes when you scroll Home or Library.

## 0.3.0 - 2026-11-05

### Changed
- Android downloads use yt-dlp, like desktop, and accept any site yt-dlp supports.
- Settings shows the yt-dlp version and an Update button on Android.
- Files are named after the video title on every platform. A name that is taken gets " (2)".

### Fixed
- Android downloads no longer stop partway through.
- Release builds on Android work on every link again.
- Titles with non-Latin characters are kept on Windows.

## 0.2.0 - 2026-11-02

### Added
- Russian, Spanish, German and Arabic. Arabic reads right to left.
- A clear button in the link field.
- Clear app data in Settings.
- A new app icon and the Ftube Downloader name.

### Changed
- Deleted files go to the system bin, with a 5 second Undo.
- Desktop opens at 800x600, and Android works in split screen and pop-up windows.
- Smaller Android downloads: one APK per processor type.
- Settings reads the tool versions once per launch.

## 0.1.0 - 2026-11-02

### Added
- First release for macOS, Windows, Linux and Android.
- Paste a video link, pick a quality or audio format, and download it.
- A download queue with progress and cancel.
- A library of downloaded files that you can open, share, rename and delete.
- Settings for the theme, language, download folder, default quality and parallel downloads.
- Desktop downloads yt-dlp, FFmpeg and Deno on first launch.
