import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../config/providers.dart';
import '../../../domain/models/models.dart';

part 'queue_view_model.freezed.dart';
part 'queue_view_model.g.dart';

@freezed
abstract class QueueState with _$QueueState {
  const factory QueueState({
    @Default(<DownloadJob>[]) List<DownloadJob> jobs,

    /// Whether a finished file can be opened on this platform.
    @Default(false) bool canOpen,
  }) = _QueueState;

  const QueueState._();

  /// Queued and running jobs, shown as the badge on Home.
  int get activeCount => jobs.where((j) => j.status.isActive).length;

  bool get hasCompleted => jobs.any((j) => j.status == JobStatus.completed);
}

/// The download queue on the Home screen.
@riverpod
class QueueViewModel extends _$QueueViewModel {
  @override
  QueueState build() {
    final repo = ref.watch(downloadRepositoryProvider);
    final sub = repo.changes.listen(
      (jobs) => state = state.copyWith(jobs: jobs),
    );
    ref.onDispose(sub.cancel);
    return QueueState(
      jobs: repo.jobs,
      canOpen: ref.watch(fileSystemServiceProvider).canOpen,
    );
  }

  Future<void> cancel(String id) =>
      ref.read(downloadRepositoryProvider).cancel(id);

  void retry(String id) => ref.read(downloadRepositoryProvider).retry(id);

  void remove(String id) => ref.read(downloadRepositoryProvider).remove(id);

  void clearFinished() => ref.read(downloadRepositoryProvider).clearFinished();

  /// Opens the finished file with the system app. Returns the error to show,
  /// or null when it opened.
  Future<Object?> open(DownloadJob job) async {
    final path = job.outputPath;
    if (path == null || !state.canOpen) return null;
    try {
      await ref.read(fileSystemServiceProvider).open(path);
      return null;
    } on Object catch (e) {
      return e;
    }
  }
}

/// Number of queued and running downloads, for the navigation badge.
@riverpod
int activeDownloadCount(Ref ref) =>
    ref.watch(queueViewModelProvider.select((s) => s.activeCount));
