import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../data/services/binaries/binary_installer.dart';

part 'setup_view_model.freezed.dart';
part 'setup_view_model.g.dart';

/// Desktop first-launch install of the binaries (D-18).
@freezed
sealed class SetupState with _$SetupState {
  /// Comparing the installed binaries with the catalog.
  const factory SetupState.checking() = SetupChecking;

  /// Some binaries are missing. [totalBytes] is what install downloads.
  const factory SetupState.needed({required int totalBytes}) = SetupNeeded;

  /// Downloading. [progress] is null until the first chunk arrives.
  const factory SetupState.installing({InstallProgress? progress}) =
      SetupInstalling;

  const factory SetupState.failed(Object error) = SetupFailed;

  /// Everything is installed, or nothing is needed on this platform.
  const factory SetupState.ready() = SetupReady;
}

@Riverpod(keepAlive: true)
class SetupViewModel extends _$SetupViewModel {
  StreamSubscription<InstallProgress>? _install;

  @override
  SetupState build() {
    ref.onDispose(() => unawaited(_install?.cancel()));
    if (ref.watch(binaryInstallerProvider) == null) {
      return const SetupState.ready();
    }
    unawaited(_check());
    return const SetupState.checking();
  }

  /// Looks for missing binaries again, for example after a failure.
  Future<void> check() async {
    if (ref.read(binaryInstallerProvider) == null) return;
    state = const SetupState.checking();
    await _check();
  }

  Future<void> _check() async {
    final installer = ref.read(binaryInstallerProvider);
    if (installer == null) return;
    try {
      // Future.sync keeps a synchronous throw from landing during build.
      final missing = await Future.sync(installer.missing);
      if (!ref.mounted) return;
      state = missing.isEmpty
          ? const SetupState.ready()
          : SetupState.needed(
              totalBytes: missing.fold(0, (sum, e) => sum + e.size),
            );
    } on Object catch (e) {
      if (ref.mounted) state = SetupState.failed(e);
    }
  }

  /// Downloads every missing binary, then checks again.
  void install() {
    final installer = ref.read(binaryInstallerProvider);
    if (installer == null || _install != null) return;
    state = const SetupState.installing();
    _install = installer.install().listen(
      (progress) => state = SetupState.installing(progress: progress),
      onError: (Object e) {
        _install = null;
        state = SetupState.failed(e);
      },
      onDone: () {
        _install = null;
        unawaited(check());
      },
      cancelOnError: true,
    );
  }

  /// Stops the download. Binaries finished so far stay installed.
  Future<void> cancel() async {
    final sub = _install;
    if (sub == null) return;
    _install = null;
    await sub.cancel();
    await check();
  }
}
