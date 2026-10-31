import '../../../domain/models/models.dart';

/// Builds yt-dlp command lines for the desktop service.
abstract final class YtDlpArgs {
  /// Prefix of the per-update line written by the download template.
  static const progressTag = 'FTUBE';

  /// Prefix of the postprocessor line (written to stderr by yt-dlp).
  static const postprocessTag = 'FTUBE_PP';

  /// Prefix of the line with the final file path.
  static const fileTag = 'FTUBE_FILE';

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
    if (preset.isAudioOnly) return 'ba/b';
    final h = preset.maxHeight;
    if (h == null) return 'bv*+ba/b';
    return 'bv*[height<=$h]+ba/b[height<=$h]';
  }

  /// Flags passed on every call, matching `ftube.sh`.
  static List<String> common({required String ffmpegDir, String? denoPath}) => [
    '--ignore-config',
    '--no-playlist',
    '--restrict-filenames',
    '--ffmpeg-location',
    ffmpegDir,
    if (denoPath != null) ...['--js-runtimes', 'deno:$denoPath'],
  ];

  /// `yt-dlp -J` for [url].
  static List<String> info(
    String url, {
    required String ffmpegDir,
    String? denoPath,
  }) => [...common(ffmpegDir: ffmpegDir, denoPath: denoPath), '-J', '--', url];

  /// A download into [outDir], with intermediate files in [tempDir].
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
      '%(title)s.%(ext)s',
      '-P',
      req.outDir.path,
      '-P',
      'temp:$tempDir',
      '--newline',
      '--progress',
      '--no-simulate',
      '--progress-template',
      _downloadTemplate,
      '--progress-template',
      _postprocessTemplate,
      '--print',
      'after_move:$fileTag|%(filepath)s',
      '--',
      req.url,
    ];
  }
}
