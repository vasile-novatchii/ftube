import 'package:freezed_annotation/freezed_annotation.dart';

import 'media_format.dart';

part 'media_info.freezed.dart';

/// Metadata of a media URL, as returned by `MediaService.fetchInfo`.
@freezed
abstract class MediaInfo with _$MediaInfo {
  const factory MediaInfo({
    required String url,
    required String title,
    String? uploader,
    Duration? duration,
    String? thumbnailUrl,
    @Default(<MediaFormat>[]) List<MediaFormat> formats,
  }) = _MediaInfo;
}
