import '../../../domain/models/models.dart';

/// Builds yt-dlp command lines for the desktop and Android services.
abstract final class YtDlpArgs {
  /// Prefix of the per-update line written by the download template.
  static const progressTag = 'FTUBE';

  /// Prefix of the postprocessor line (written to stderr by yt-dlp).
  static const postprocessTag = 'FTUBE_PP';

  /// Prefix of the line with the final file path.
  static const fileTag = 'FTUBE_FILE';

  /// Prefix of the line with the video title.
  static const titleTag = 'FTUBE_TITLE';

  static const _downloadTemplate =
      'download:$progressTag'
      '|%(progress.status)s'
      '|%(progress.downloaded_bytes)s'
      '|%(progress.total_bytes)s'
      '|%(progress.total_bytes_estimate)s'
      '|%(progress.speed)s'
      '|%(progress.eta)s'
      '|%(info.vcodec)s';

  static const _postprocessTemplate =
      'postprocess:$postprocessTag'
      '|%(progress.status)s'
      '|%(progress.postprocessor)s';

  /// Format selector for [preset], or [formatId] for [QualityPreset.custom].
  ///
  /// A custom [formatId] is passed through as is, so callers can send a full
  /// selector such as `399+ba` for a video-only format.
  static String formatSelector(QualityPreset preset, {String? formatId}) {
    if (preset == QualityPreset.custom) {
      if (formatId == null || formatId.isEmpty) {
        throw ArgumentError.value(formatId, 'formatId', 'required for custom');
      }
      return formatId;
    }
    if (preset == QualityPreset.audioM4a) return 'ba[ext=m4a]/ba/b';
    if (preset.isAudioOnly) return 'ba/b';
    final h = preset.maxHeight;
    if (h == null) return 'bv*+ba/b';
    return 'bv*[height<=$h]+ba/b[height<=$h]';
  }

  /// Flags passed on every call, matching `ftube.sh`. `--encoding utf-8`
  /// keeps non-Latin titles on Windows, where yt-dlp otherwise writes the
  /// pipe in the ANSI code page and drops what it cannot encode.
  static List<String> common({required String ffmpegDir, String? denoPath}) => [
    '--ignore-config',
    '--no-playlist',
    '--encoding',
    'utf-8',
    '--ffmpeg-location',
    ffmpegDir,
    if (denoPath != null) ...['--js-runtimes', 'deno:$denoPath'],
  ];

  /// Most playlist entries one fetch reads (spec-v0.5 D-56).
  static const playlistLimit = 200;

  /// Info flags: playlists come back as a flat list of their first
  /// [playlistLimit] entries (D-55, D-56). [playlist] reads the playlist of
  /// a `watch?v=…&list=…` link instead of its video. The later
  /// `--yes-playlist` overrides `--no-playlist`.
  static List<String> _info(String url, {required bool playlist}) => [
    if (playlist) '--yes-playlist',
    '--flat-playlist',
    '-I',
    '1:$playlistLimit',
    '-J',
    '--',
    url,
  ];

  /// `yt-dlp -J` for [url].
  static List<String> info(
    String url, {
    required String ffmpegDir,
    String? denoPath,
    bool playlist = false,
  }) => [
    ...common(ffmpegDir: ffmpegDir, denoPath: denoPath),
    ..._info(url, playlist: playlist),
  ];

  /// A download into [tempDir] as `media.<ext>`. The service then moves
  /// it to `outDir` under the title (spec-v0.3 D-39), so yt-dlp never sees
  /// or replaces files already there.
  static List<String> download(
    DownloadRequest req, {
    required String ffmpegDir,
    required String tempDir,
    String? denoPath,
  }) {
    final audio = req.preset.audioTarget;
    return [
      ...common(ffmpegDir: ffmpegDir, denoPath: denoPath),
      '-f',
      formatSelector(req.preset, formatId: req.formatId),
      if (audio != null) ...[
        '-x',
        '--audio-format',
        switch (audio) {
          AudioTarget.mp3 => 'mp3',
          AudioTarget.ogg => 'vorbis',
        },
        '--audio-quality',
        '0',
      ],
      '-o',
      'media.%(ext)s',
      '-P',
      tempDir,
      '--newline',
      '--progress',
      '--no-simulate',
      '--progress-template',
      _downloadTemplate,
      '--progress-template',
      _postprocessTemplate,
      '--print',
      'video:$titleTag|%(title)s',
      '--print',
      'after_move:$fileTag|%(filepath)s',
      '--',
      req.url,
    ];
  }

  /// `yt-dlp -J` on Android. youtubedl-android adds `--ffmpeg-location` and
  /// `--js-runtimes` itself (spec-v0.3 D-31).
  static List<String> androidInfo(String url, {bool playlist = false}) => [
    '--ignore-config',
    '--no-playlist',
    ..._info(url, playlist: playlist),
  ];

  /// A download on Android into [tempDir] (spec-v0.3 D-34). yt-dlp has no
  /// working ffmpeg there, so it leaves video and audio as separate
  /// `media.f<id>.<ext>` files; the service muxes or converts them.
  static List<String> androidDownload(
    DownloadRequest req, {
    required String tempDir,
  }) => [
    '--ignore-config',
    '--no-playlist',
    '-f',
    formatSelector(req.preset, formatId: req.formatId),
    '-o',
    'media.%(ext)s',
    '-P',
    tempDir,
    '--newline',
    '--progress',
    '--no-simulate',
    '--progress-template',
    _downloadTemplate,
    '--print',
    'video:$titleTag|%(title)s',
    '--',
    req.url,
  ];
}
