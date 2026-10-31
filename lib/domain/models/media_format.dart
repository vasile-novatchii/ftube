import 'package:freezed_annotation/freezed_annotation.dart';

part 'media_format.freezed.dart';

/// What a single format stream contains.
enum FormatKind { videoAudio, videoOnly, audioOnly }

/// One downloadable format of a media item.
@freezed
abstract class MediaFormat with _$MediaFormat {
  const factory MediaFormat({
    required String id,
    required String container,
    required FormatKind kind,
    String? resolution,
    int? height,
    int? fps,
    int? bitrateKbps,
    int? sizeBytes,
  }) = _MediaFormat;
}
