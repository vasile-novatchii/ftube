import 'dart:convert';

import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';
import 'yt_dlp_args.dart';

/// One machine-readable line written by yt-dlp with the templates from
/// [YtDlpArgs].
sealed class YtDlpLine {
  const YtDlpLine();
}

/// A download progress update for one format stream.
final class YtDlpDownloadLine extends YtDlpLine {
  const YtDlpDownloadLine({
    required this.finished,
    required this.isAudio,
    this.downloadedBytes,
    this.totalBytes,
    this.speedBps,
    this.eta,
  });

  final bool finished;

  /// The stream being downloaded has no video codec.
  final bool isAudio;
  final int? downloadedBytes;

  /// Exact size, or yt-dlp's estimate when the exact one is unknown.
  final int? totalBytes;
  final double? speedBps;
  final Duration? eta;

  /// Progress of this stream, 0..1, or null when the size is unknown.
  double? get fraction {
    final done = downloadedBytes;
    final total = totalBytes;
    if (finished) return 1;
    if (done == null || total == null || total <= 0) return null;
    return (done / total).clamp(0.0, 1.0);
  }
}

/// A postprocessor (Merger, ExtractAudio, MoveFiles, ...) started or ended.
final class YtDlpPostprocessLine extends YtDlpLine {
  const YtDlpPostprocessLine({required this.started, required this.name});

  final bool started;
  final String name;

  /// The job phase this postprocessor stands for, if any.
  JobPhase? get phase => switch (name) {
    'Merger' => JobPhase.merging,
    'ExtractAudio' => JobPhase.converting,
    _ => null,
  };
}

/// The final path of the downloaded file.
final class YtDlpFileLine extends YtDlpLine {
  const YtDlpFileLine(this.path);

  final String path;
}

/// The video title, printed before the download starts (Android).
final class YtDlpTitleLine extends YtDlpLine {
  const YtDlpTitleLine(this.title);

  final String title;
}

/// yt-dlp started writing one format to [path].
final class YtDlpDestinationLine extends YtDlpLine {
  const YtDlpDestinationLine(this.path);

  final String path;
}

/// Parses yt-dlp JSON and progress output.
abstract final class YtDlpOutput {
  /// Parses one output line, or returns null for any other line.
  static YtDlpLine? parseLine(String line) {
    const destination = '[download] Destination: ';
    if (line.startsWith(destination)) {
      return YtDlpDestinationLine(line.substring(destination.length).trim());
    }
    final parts = line.trimRight().split('|');
    switch (parts.first) {
      case YtDlpArgs.progressTag when parts.length >= 8:
        return YtDlpDownloadLine(
          finished: parts[1] == 'finished',
          downloadedBytes: _num(parts[2])?.round(),
          totalBytes: (_num(parts[3]) ?? _num(parts[4]))?.round(),
          speedBps: _num(parts[5])?.toDouble(),
          eta: switch (_num(parts[6])) {
            final s? => Duration(seconds: s.round()),
            null => null,
          },
          isAudio: parts[7] == 'none',
        );
      case YtDlpArgs.postprocessTag when parts.length >= 3:
        return YtDlpPostprocessLine(
          started: parts[1] == 'started',
          name: parts[2],
        );
      case YtDlpArgs.titleTag when parts.length >= 2:
        return YtDlpTitleLine(parts.sublist(1).join('|'));
      case YtDlpArgs.fileTag when parts.length >= 2:
        // The path itself may contain '|'.
        return YtDlpFileLine(parts.sublist(1).join('|'));
      default:
        return null;
    }
  }

  static num? _num(String s) => s == 'NA' ? null : num.tryParse(s);

  /// Parses `yt-dlp -J --flat-playlist` output: a video, or a playlist
  /// with its entries (spec-v0.5 D-62). Storyboards and other formats with
  /// neither audio nor video are skipped.
  static FetchResult parseInfo(String json, {required String url}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw Unsupported('invalid yt-dlp JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const Unsupported('yt-dlp JSON is not an object');
    }
    if (decoded['_type'] == 'playlist') return _playlist(decoded, url);
    final duration = decoded['duration'];
    final formats = decoded['formats'];
    return MediaInfo(
      url: url,
      title: (decoded['title'] as String?) ?? url,
      uploader: (decoded['uploader'] ?? decoded['channel']) as String?,
      duration: _duration(duration),
      thumbnailUrl: decoded['thumbnail'] as String?,
      formats: [
        if (formats is List<Object?>)
          for (final f in formats.whereType<Map<String, Object?>>())
            ?_format(f),
      ],
    );
  }

  static Duration? _duration(Object? seconds) =>
      seconds is num ? Duration(milliseconds: (seconds * 1000).round()) : null;

  static PlaylistInfo _playlist(Map<String, Object?> p, String url) {
    final raw = p['entries'];
    final entries = [
      if (raw is List<Object?>)
        for (final e in raw.whereType<Map<String, Object?>>()) ?_entry(e),
    ];
    if (entries.isEmpty) throw const Unsupported('empty playlist');
    final count = p['playlist_count'];
    final total = count is num ? count.round() : null;
    return PlaylistInfo(
      url: url,
      title: (p['title'] as String?) ?? url,
      uploader: (p['uploader'] ?? p['channel']) as String?,
      totalCount: total,
      entries: entries,
      // YouTube channel tabs give no count; a full first page may have more.
      truncated: total != null
          ? total > entries.length
          : raw is List<Object?> && raw.length >= YtDlpArgs.playlistLimit,
    );
  }

  static const _unavailableTitles = {'[Private video]', '[Deleted video]'};
  static const _unavailable = {
    'private',
    'needs_auth',
    'premium_only',
    'subscriber_only',
  };
  static final _listIe = RegExp(r'(Tab|Playlist|Channel|Album|Set|User)$');

  static PlaylistEntry? _entry(Map<String, Object?> e) {
    final ie = e['ie_key'] as String?;
    final id = e['id'] as String?;
    final url =
        (e['url'] ?? e['webpage_url']) as String? ??
        (ie == 'Youtube' && id != null
            ? 'https://www.youtube.com/watch?v=$id'
            : null);
    if (url == null) return null;
    final title = e['title'] as String?;
    final thumbs = e['thumbnails'];
    final last = thumbs is List<Object?>
        ? thumbs.whereType<Map<String, Object?>>().lastOrNull
        : null;
    final thumb = (e['thumbnail'] ?? last?['url']) as String?;
    return PlaylistEntry(
      url: url,
      title: title ?? url,
      duration: _duration(e['duration']),
      thumbnailUrl: thumb,
      isList: e['_type'] == 'playlist' || (ie != null && _listIe.hasMatch(ie)),
      unavailable:
          _unavailableTitles.contains(title) ||
          _unavailable.contains(e['availability']),
    );
  }

  static MediaFormat? _format(Map<String, Object?> f) {
    final id = f['format_id'];
    if (id is! String) return null;
    final vcodec = f['vcodec'] as String?;
    final acodec = f['acodec'] as String?;
    final resolution = f['resolution'] as String?;
    final hasVideo = vcodec != 'none' && resolution != 'audio only';
    final hasAudio = acodec != 'none';
    if (!hasVideo && !hasAudio) return null;
    if (f['protocol'] == 'mhtml') return null;
    final kind = switch ((hasVideo, hasAudio)) {
      (true, true) => FormatKind.videoAudio,
      (true, false) => FormatKind.videoOnly,
      _ => FormatKind.audioOnly,
    };
    int? asInt(Object? v) => v is num ? v.round() : null;
    return MediaFormat(
      id: id,
      container: (f['ext'] as String?) ?? '?',
      kind: kind,
      resolution: kind == FormatKind.audioOnly ? null : resolution,
      height: asInt(f['height']),
      fps: asInt(f['fps']),
      bitrateKbps: asInt(f['tbr'] ?? f['abr'] ?? f['vbr']),
      sizeBytes: asInt(f['filesize'] ?? f['filesize_approx']),
    );
  }

  static final _network = RegExp(
    'TransportError|timed out|Failed to resolve|Name or service not known|'
    'nodename nor servname|getaddrinfo failed|'
    'Temporary failure in name resolution|Network is unreachable|'
    'Connection refused|Connection reset|No address associated',
    caseSensitive: false,
  );

  /// Maps a failed yt-dlp run to a typed exception.
  static FtubeException mapError(int exitCode, String stderr) {
    final errors = stderr
        .split(RegExp(r'\r?\n'))
        .where((l) => l.startsWith('ERROR:'))
        .join('\n');
    final text = errors.isEmpty ? stderr : errors;
    if (text.contains('Unsupported URL')) return Unsupported(text.trim());
    if (text.contains('is not a valid URL')) return InvalidUrl(text.trim());
    if (_network.hasMatch(text)) return Network(text.trim());
    return ProcessFailed.fromStderr(exitCode, stderr);
  }
}
