import 'package:flutter/widgets.dart';

import '../../domain/exceptions/ftube_exception.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';

export '../../l10n/generated/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension AppLocalizationsLabels on AppLocalizations {
  String themeLabel(ThemePreference theme) => switch (theme) {
    ThemePreference.system => themeSystem,
    ThemePreference.light => themeLight,
    ThemePreference.dark => themeDark,
  };

  String languageLabel(AppLanguage language) => switch (language) {
    AppLanguage.en => languageEn,
    AppLanguage.ro => languageRo,
  };

  String presetLabel(QualityPreset preset) => switch (preset) {
    QualityPreset.best => presetBest,
    QualityPreset.p1080 => presetP1080,
    QualityPreset.p720 => presetP720,
    QualityPreset.p480 => presetP480,
    QualityPreset.audioMp3 => presetAudioMp3,
    QualityPreset.audioOgg => presetAudioOgg,
    QualityPreset.custom => presetCustom,
  };

  String formatKindLabel(FormatKind kind) => switch (kind) {
    FormatKind.videoAudio => formatVideoAudio,
    FormatKind.videoOnly => formatVideoOnly,
    FormatKind.audioOnly => formatAudioOnly,
  };

  /// One line per format, for example `1080p60 · mp4 · video only · 12 MB`.
  String formatLabel(MediaFormat f) => [
    ?f.resolution,
    f.container,
    formatKindLabel(f.kind),
    if (f.bitrateKbps case final kbps?) formatKbps(kbps),
    if (f.sizeBytes case final size?) formatBytes(size),
  ].join(' · ');

  String phaseLabel(JobPhase phase) => switch (phase) {
    JobPhase.downloadingVideo => phaseDownloadingVideo,
    JobPhase.downloadingAudio => phaseDownloadingAudio,
    JobPhase.merging => phaseMerging,
    JobPhase.converting => phaseConverting,
    JobPhase.finished => statusCompleted,
  };

  /// What a queue row says about [job] besides its progress numbers.
  String jobStatusLabel(DownloadJob job) => switch (job.status) {
    JobStatus.queued => statusQueued,
    JobStatus.running => switch (job.progress) {
      final p? => phaseLabel(p.phase),
      null => statusStarting,
    },
    JobStatus.completed => statusCompleted,
    JobStatus.failed => errorMessage(job.error ?? const Unexpected()),
    JobStatus.cancelled => statusCancelled,
  };

  /// A user-facing message for [error]. Technical details stay in logs.
  String errorMessage(Object error) => switch (error) {
    InvalidUrl() => errorInvalidUrl,
    Unsupported() => errorUnsupported,
    Network() => errorNetwork,
    BinaryMissing(:final binary) => errorBinaryMissing(binary),
    ChecksumMismatch(:final binary) => errorChecksum(binary),
    ProcessFailed(:final exitCode) => errorProcessFailed(exitCode),
    StoragePermission() => errorStoragePermission,
    Cancelled() => errorCancelled,
    InvalidFileName() => errorInvalidFileName,
    FileExists(:final name) => errorFileExists(name),
    FileError() => errorFile,
    _ => errorUnknown,
  };
}

/// Human-readable size, for example `12.3 MB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// `m:ss`, or `h:mm:ss` from one hour.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}
