import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/repositories/download_starter.dart';
import '../../../data/services/android/share_link_service.dart';
import '../../../data/services/android/storage_permission_service.dart';
import '../../../domain/models/models.dart';
import '../../home/view_model/home_view_model.dart';

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

/// Presets on the popup's Video tab, highest first.
const shareVideoPresets = [
  QualityPreset.best,
  QualityPreset.p1080,
  QualityPreset.p720,
  QualityPreset.p480,
  QualityPreset.p360,
];

/// Presets on the popup's Audio tab.
const shareAudioPresets = [
  QualityPreset.audioMp3,
  QualityPreset.audioM4a,
  QualityPreset.audioOgg,
];

/// Whether [preset] gives something for a video with [formats]
/// (spec-v0.4-share D-73). A height chip needs a video stream above the
/// next lower chip, so each chip gives a different download. Best, MP3 and
/// OGG always work; M4A needs an M4A audio stream.
bool sharePresetAvailable(QualityPreset preset, List<MediaFormat> formats) {
  if (preset == QualityPreset.audioM4a) {
    return formats.any(
      (f) => f.kind == FormatKind.audioOnly && f.container == 'm4a',
    );
  }
  final max = preset.maxHeight;
  if (max == null) return true;
  final i = shareVideoPresets.indexOf(preset);
  final lower = i + 1 < shareVideoPresets.length
      ? shareVideoPresets[i + 1].maxHeight ?? 0
      : 0;
  return formats.any(
    (f) =>
        f.kind != FormatKind.audioOnly &&
        f.height != null &&
        f.height! > lower &&
        f.height! <= max,
  );
}

@freezed
abstract class ShareState with _$ShareState {
  const factory ShareState({
    /// The chosen chip, never [QualityPreset.custom].
    required QualityPreset preset,

    /// Null when the shared text had no link.
    String? url,

    /// What is known before yt-dlp has loaded: the shared title and the
    /// YouTube thumbnail (spec-v0.4-share D-64).
    MediaInfo? preview,
    @Default(false) bool fetching,

    /// The video as yt-dlp loaded it, with its formats.
    MediaInfo? info,
    Object? error,

    /// Android: storage access is missing (D-54).
    @Default(false) bool noAccess,

    /// Download was tapped and the job is being queued.
    @Default(false) bool queuing,

    /// The link is a playlist, which only Home can download
    /// (spec-v0.5 D-79).
    @Default(false) bool isPlaylist,
  }) = _ShareState;

  const ShareState._();

  bool get audio => preset.isAudioOnly;

  /// The chips of the current tab: all of them while loading, then only
  /// those the video has (D-73, D-74).
  List<QualityPreset> get presets => _tab(audio: audio);

  List<QualityPreset> _tab({required bool audio}) {
    final all = audio ? shareAudioPresets : shareVideoPresets;
    final formats = info?.formats;
    if (formats == null) return all;
    return [
      for (final p in all)
        if (sharePresetAvailable(p, formats)) p,
    ];
  }

  /// [preset], or the tab's first chip when the video lacks it.
  QualityPreset _supported(QualityPreset preset) {
    final tab = _tab(audio: preset.isAudioOnly);
    return tab.contains(preset) ? preset : tab.first;
  }

  /// The card's content: the loaded video, or the preview until then.
  MediaInfo? get shown => info ?? preview;

  /// Download works from the start with a chip (D-65); a fetch error turns
  /// it off, since yt-dlp would fail the same way.
  bool get canDownload =>
      shown != null && !noAccess && !queuing && !isPlaylist && error == null;
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
    final share = ref.watch(shareSessionProvider.select((r) => r));
    final url = share?.url;
    final preset = _defaultPreset();
    if (url == null) return ShareState(preset: preset);
    if (isPlaylistLink(url)) {
      return ShareState(url: url, preset: preset, isPlaylist: true);
    }
    unawaited(Future.microtask(() => _load(++_seq, url)));
    return ShareState(
      url: url,
      preset: preset,
      fetching: true,
      preview: MediaInfo(
        url: url,
        title: share?.subject ?? url,
        thumbnailUrl: youtubeThumbnail(url),
      ),
    );
  }

  /// Clears an error; loads the video again if it wasn't loaded.
  Future<void> retry() async {
    final url = state.url;
    if (url == null || state.fetching) return;
    if (state.info != null) {
      state = state.copyWith(error: null);
      return;
    }
    state = state.copyWith(fetching: true, error: null);
    await _load(++_seq, url);
  }

  /// Switches between the Video and Audio tabs.
  void selectTab({required bool audio}) {
    if (audio == state.audio) return;
    final preset = _defaultPreset();
    state = state.copyWith(
      preset: state._supported(
        preset.isAudioOnly == audio
            ? preset
            : (audio ? shareAudioPresets : shareVideoPresets).first,
      ),
    );
  }

  void selectPreset(QualityPreset preset) {
    if (preset == QualityPreset.custom) {
      throw ArgumentError.value(preset, 'preset', 'not a share chip');
    }
    state = state.copyWith(preset: preset);
  }

  /// Opens the app on Home with the playlist link (spec-v0.5 D-79).
  Future<void> openInApp() async {
    final url = state.url;
    if (url == null) return;
    unawaited(ref.read(homeViewModelProvider.notifier).openLink(url));
    await ref.read(shareSessionProvider.notifier).openApp();
  }

  /// Queues the video and closes the popup with [toast].
  Future<void> download({required String toast}) async {
    final info = state.shown;
    if (info == null || !state.canDownload) return;
    state = state.copyWith(queuing: true);
    try {
      await ref.read(downloadStarterProvider).start(info, state.preset);
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
      if (info is! MediaInfo) {
        state = state.copyWith(
          fetching: false,
          isPlaylist: true,
          noAccess: false,
        );
        return;
      }
      final loaded = state.copyWith(
        fetching: false,
        info: info,
        noAccess: false,
      );
      state = loaded.copyWith(preset: loaded._supported(loaded.preset));
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
