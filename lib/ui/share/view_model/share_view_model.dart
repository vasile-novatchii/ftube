import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/repositories/download_starter.dart';
import '../../../data/services/android/share_link_service.dart';
import '../../../data/services/android/storage_permission_service.dart';
import '../../../domain/models/models.dart';

part 'share_view_model.freezed.dart';
part 'share_view_model.g.dart';

/// The open share, or null when the app is shown instead of the popup
/// (spec-v0.4-share D-50).
@Riverpod(keepAlive: true)
class ShareSession extends _$ShareSession {
  @override
  ShareRequest? build() {
    final service = ref.watch(shareLinkServiceProvider);
    if (service == null) return null;
    final sub = service.requests.listen((r) => state = r);
    ref.onDispose(sub.cancel);
    return service.current;
  }

  /// Closes the popup. Android ends the session once the window is gone,
  /// so the app isn't drawn in it meanwhile.
  Future<void> close({String? toast}) async {
    final service = ref.read(shareLinkServiceProvider);
    if (service == null || !await service.close(toast: toast)) _end();
  }

  /// Opens the app, for example to grant storage access (D-54).
  Future<void> openApp() async {
    final service = ref.read(shareLinkServiceProvider);
    if (service == null || !await service.openApp()) _end();
  }

  void _end() {
    if (ref.mounted) state = null;
  }
}

/// Presets on the popup's Video tab.
const shareVideoPresets = [
  QualityPreset.best,
  QualityPreset.p1080,
  QualityPreset.p720,
  QualityPreset.p480,
];

/// Presets on the popup's Audio tab.
const shareAudioPresets = [QualityPreset.audioMp3, QualityPreset.audioOgg];

@freezed
abstract class ShareState with _$ShareState {
  const factory ShareState({
    /// The chosen chip, never [QualityPreset.custom]; [formatId] overrides it.
    required QualityPreset preset,

    /// Null when the shared text had no link.
    String? url,
    @Default(false) bool fetching,
    MediaInfo? info,
    Object? error,

    /// A format picked from the format menu.
    String? formatId,

    /// Android: storage access is missing (D-54).
    @Default(false) bool noAccess,

    /// Download was tapped and the job is being queued.
    @Default(false) bool queuing,
  }) = _ShareState;

  const ShareState._();

  bool get audio => preset.isAudioOnly;

  List<QualityPreset> get presets =>
      audio ? shareAudioPresets : shareVideoPresets;

  /// The formats for the current tab.
  List<MediaFormat> get formats => [
    for (final f in info?.formats ?? const <MediaFormat>[])
      if ((f.kind == FormatKind.audioOnly) == audio) f,
  ];

  MediaFormat? get selectedFormat =>
      formats.where((f) => f.id == formatId).firstOrNull;

  bool get canDownload =>
      info != null && !fetching && !noAccess && !queuing && error == null;
}

/// The share popup: reads the shared link, lets the user pick a format and
/// queues it (spec-v0.4-share D-53). Never downloads by itself. Starts over
/// when a new share replaces the link.
@riverpod
class ShareViewModel extends _$ShareViewModel {
  /// Guards against an older load overwriting a newer one.
  var _seq = 0;

  @override
  ShareState build() {
    final url = ref.watch(shareSessionProvider.select((r) => r))?.url;
    final preset = _defaultPreset();
    if (url != null) unawaited(Future.microtask(() => _load(++_seq, url)));
    return ShareState(url: url, preset: preset, fetching: url != null);
  }

  Future<void> retry() async {
    final url = state.url;
    if (url == null || state.fetching) return;
    state = state.copyWith(fetching: true, error: null);
    await _load(++_seq, url);
  }

  /// Switches between the Video and Audio tabs.
  void selectTab({required bool audio}) {
    if (audio == state.audio) return;
    final preset = _defaultPreset();
    state = state.copyWith(
      preset: preset.isAudioOnly == audio
          ? preset
          : (audio ? shareAudioPresets : shareVideoPresets).first,
      formatId: null,
    );
  }

  void selectPreset(QualityPreset preset) {
    if (preset == QualityPreset.custom) {
      throw ArgumentError.value(preset, 'preset', 'use selectFormat');
    }
    state = state.copyWith(preset: preset, formatId: null);
  }

  /// Picks a format of the current tab, or the chosen chip again for null.
  void selectFormat(String? formatId) =>
      state = state.copyWith(formatId: formatId);

  /// Queues the video and closes the popup with [toast].
  Future<void> download({required String toast}) async {
    final info = state.info;
    if (info == null || !state.canDownload) return;
    state = state.copyWith(queuing: true);
    try {
      await ref
          .read(downloadStarterProvider)
          .start(info, state.preset, format: state.selectedFormat);
    } on StorageBlocked {
      if (ref.mounted) state = state.copyWith(queuing: false, noAccess: true);
      return;
    } on Object catch (e) {
      if (ref.mounted) state = state.copyWith(queuing: false, error: e);
      return;
    }
    await ref.read(shareSessionProvider.notifier).close(toast: toast);
  }

  Future<void> _load(int seq, String url) async {
    try {
      final storage = ref.read(storagePermissionServiceProvider);
      if (storage != null && await storage.status() != StorageAccess.granted) {
        if (ref.mounted && seq == _seq) {
          state = state.copyWith(fetching: false, noAccess: true);
        }
        return;
      }
      final info = await ref.read(mediaServiceProvider).fetchInfo(url);
      if (!ref.mounted || seq != _seq) return;
      state = state.copyWith(fetching: false, info: info, noAccess: false);
    } on Object catch (e) {
      if (!ref.mounted || seq != _seq) return;
      state = state.copyWith(fetching: false, error: e);
    }
  }

  QualityPreset _defaultPreset() {
    final preset = ref.read(currentSettingsProvider).defaultPreset;
    return preset == QualityPreset.custom ? QualityPreset.best : preset;
  }
}
