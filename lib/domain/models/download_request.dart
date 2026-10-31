import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'quality_preset.dart';

part 'download_request.freezed.dart';

/// Everything a `MediaService` needs to run one download.
@freezed
abstract class DownloadRequest with _$DownloadRequest {
  @Assert(
    'preset != QualityPreset.custom || formatId != null',
    'custom preset requires a formatId',
  )
  const factory DownloadRequest({
    required String jobId,
    required String url,
    required QualityPreset preset,
    required Directory outDir,
    String? formatId,
  }) = _DownloadRequest;
}
