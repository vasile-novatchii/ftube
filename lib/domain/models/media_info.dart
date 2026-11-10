import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_format.dart';

part 'media_info.freezed.dart';

/// What `MediaService.fetchInfo` returns: one video, or a playlist
/// (spec-v0.5 section 2).
sealed class FetchResult {
  String get url;
  String get title;
}

/// Metadata of a media URL, as returned by `MediaService.fetchInfo`.
@freezed
abstract class MediaInfo with _$MediaInfo implements FetchResult {
  const factory MediaInfo({
    required String url,
    required String title,
    String? uploader,
    Duration? duration,
    String? thumbnailUrl,
    @Default(<MediaFormat>[]) List<MediaFormat> formats,
  }) = _MediaInfo;
}

/// A playlist or channel, read with `--flat-playlist` (spec-v0.5 D-55).
@freezed
abstract class PlaylistInfo with _$PlaylistInfo implements FetchResult {
  const factory PlaylistInfo({
    required String url,
    required String title,
    String? uploader,

    /// All entries the playlist has, when yt-dlp knows it.
    int? totalCount,
    @Default(<PlaylistEntry>[]) List<PlaylistEntry> entries,

    /// More entries exist than were read (D-56).
    @Default(false) bool truncated,
  }) = _PlaylistInfo;
}

/// One entry of a [PlaylistInfo].
@freezed
abstract class PlaylistEntry with _$PlaylistEntry {
  const factory PlaylistEntry({
    required String url,
    required String title,
    Duration? duration,
    String? thumbnailUrl,

    /// The entry is a list itself, such as a channel's Videos tab.
    @Default(false) bool isList,

    /// A private or deleted video, which can't be downloaded.
    @Default(false) bool unavailable,
  }) = _PlaylistEntry;

  const PlaylistEntry._();

  /// Whether the entry can be queued.
  bool get downloadable => !isList && !unavailable;
}
