import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/repositories/download_starter.dart';
import '../../../data/services/android/storage_permission_service.dart';
import '../../../domain/exceptions/ftube_exception.dart';
import '../../../domain/models/models.dart';

export '../../../data/repositories/download_starter.dart' show NoDownloadFolder;

part 'home_view_model.freezed.dart';
part 'home_view_model.g.dart';

@freezed
abstract class HomeState with _$HomeState {
  const factory HomeState({
    required QualityPreset preset,
    @Default('') String url,
    @Default(false) bool fetching,
    MediaInfo? info,

    /// The last fetch or download error, cleared by the next action.
    Object? error,

    /// Set with [QualityPreset.custom].
    String? formatId,

    /// A link found on the clipboard, offered once.
    String? clipboardUrl,

    /// Android: storage access is missing, so downloads are blocked.
    @Default(false) bool storageBlocked,
  }) = _HomeState;

  const HomeState._();

  bool get canFetch => url.trim().isNotEmpty && !fetching;

  bool get canDownload =>
      info != null &&
      !fetching &&
      !storageBlocked &&
      (preset != QualityPreset.custom || formatId != null);

  MediaFormat? get selectedFormat => preset == QualityPreset.custom
      ? info?.formats.where((f) => f.id == formatId).firstOrNull
      : null;
}

/// Presets offered as chips; [QualityPreset.custom] is picked through the
/// format list instead.
const homePresets = [
  QualityPreset.best,
  QualityPreset.p1080,
  QualityPreset.p720,
  QualityPreset.p480,
  QualityPreset.audioMp3,
  QualityPreset.audioOgg,
];

/// Whether [text] is an http(s) link.
bool isWebUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Home screen: paste a link, read its info, pick a quality, download.
/// Kept alive so a fetched video survives switching tabs.
@Riverpod(keepAlive: true)
class HomeViewModel extends _$HomeViewModel {
  /// Guards against an older fetch overwriting a newer one.
  var _fetchSeq = 0;

  /// The last clipboard link offered, so it is offered only once.
  String? _offered;

  @override
  HomeState build() {
    ref.listen(currentSettingsProvider.select((s) => s.defaultPreset), (
      _,
      preset,
    ) {
      if (state.info == null) state = state.copyWith(preset: preset);
    });
    return HomeState(preset: ref.read(currentSettingsProvider).defaultPreset);
  }

  void setUrl(String url) => state = state.copyWith(url: url, error: null);

  /// Reads info for the current link.
  Future<void> fetch() async {
    final url = state.url.trim();
    if (url.isEmpty || state.fetching) return;
    final seq = ++_fetchSeq;
    if (!isWebUrl(url)) {
      state = state.copyWith(info: null, error: const InvalidUrl());
      return;
    }
    state = state.copyWith(
      url: url,
      fetching: true,
      info: null,
      error: null,
      formatId: null,
      preset: state.preset == QualityPreset.custom
          ? ref.read(currentSettingsProvider).defaultPreset
          : state.preset,
    );
    try {
      final info = await ref.read(mediaServiceProvider).fetchInfo(url);
      if (!ref.mounted || seq != _fetchSeq) return;
      state = state.copyWith(fetching: false, info: info);
    } on Object catch (e) {
      if (!ref.mounted || seq != _fetchSeq) return;
      state = state.copyWith(fetching: false, error: e);
    }
  }

  /// Pastes the clipboard into the link field and fetches it.
  Future<void> paste() async {
    final text = (await _readClipboard())?.trim();
    if (text == null || text.isEmpty || !ref.mounted) return;
    _offered = text;
    state = state.copyWith(url: text, clipboardUrl: null, error: null);
    await fetch();
  }

  /// Offers a link found on the clipboard, unless it is already in the
  /// field or was offered before.
  Future<void> checkClipboard() async {
    final text = (await _readClipboard())?.trim();
    if (text == null || !ref.mounted) return;
    if (!isWebUrl(text) || text == state.url.trim() || text == _offered) {
      return;
    }
    _offered = text;
    state = state.copyWith(clipboardUrl: text);
  }

  Future<void> useClipboard() async {
    final url = state.clipboardUrl;
    if (url == null) return;
    state = state.copyWith(url: url, clipboardUrl: null, error: null);
    await fetch();
  }

  void dismissClipboard() => state = state.copyWith(clipboardUrl: null);

  void selectPreset(QualityPreset preset) {
    if (preset == QualityPreset.custom) {
      throw ArgumentError.value(preset, 'preset', 'use selectFormat');
    }
    state = state.copyWith(preset: preset, formatId: null);
  }

  void selectFormat(String formatId) =>
      state = state.copyWith(preset: QualityPreset.custom, formatId: formatId);

  /// Queues the fetched video with the chosen quality. Returns the job, or
  /// null when it could not be queued; [HomeState.error] or
  /// [HomeState.storageBlocked] then says why.
  Future<DownloadJob?> download() async {
    final info = state.info;
    if (info == null || !state.canDownload) return null;
    try {
      final job = await ref
          .read(downloadStarterProvider)
          .start(info, state.preset, format: state.selectedFormat);
      if (ref.mounted) state = state.copyWith(error: null);
      return job;
    } on StorageBlocked {
      if (ref.mounted) state = state.copyWith(storageBlocked: true);
    } on NoDownloadFolder catch (e) {
      if (ref.mounted) state = state.copyWith(error: e);
    }
    return null;
  }

  /// Android: asks for storage access, or opens the app settings when
  /// Android will not ask again.
  Future<void> grantStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null) return;
    var access = await storage.request();
    if (access == StorageAccess.permanentlyDenied) {
      await storage.openSettings();
      access = await storage.status();
    }
    if (ref.mounted) {
      state = state.copyWith(storageBlocked: access != StorageAccess.granted);
    }
  }

  /// Android: re-checks a blocked storage access, for example when the user
  /// comes back from system settings.
  Future<void> refreshStorageAccess() async {
    final storage = ref.read(storagePermissionServiceProvider);
    if (storage == null || !state.storageBlocked) return;
    final access = await storage.status();
    if (ref.mounted && access == StorageAccess.granted) {
      state = state.copyWith(storageBlocked: false);
    }
  }

  Future<String?> _readClipboard() async {
    try {
      return await ref.read(clipboardReaderProvider)();
    } on Object {
      return null;
    }
  }
}
