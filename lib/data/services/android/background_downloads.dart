import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../../domain/models/models.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../repositories/download_repository.dart';
import 'notification_permission.dart';

/// What the ongoing notification shows (spec-v0.4 D-46).
class BackgroundSummary {
  const BackgroundSummary({
    required this.current,
    required this.total,
    required this.title,
    this.percent,
  });

  /// The job being worked on, counting from 1 since the service started.
  final int current;

  /// Jobs seen since the service started.
  final int total;

  /// Mean progress of the running jobs, 0..100, or null when unknown.
  final int? percent;

  /// Title of the first running (else queued) job.
  final String title;
}

/// Keeps `DownloadService.kt` in step with the queue, so Android keeps the
/// process alive while jobs run (spec-v0.4 D-40, D-45, D-46).
///
/// A session starts with the first active job and ends when none is left.
/// While only paused jobs are left, the service stops and a paused
/// notification stays (D-70). Updates are throttled to one a second.
class BackgroundDownloads {
  BackgroundDownloads({
    required DownloadRepository repository,
    required this._l10n,
    this._notifications,
    this._channel = BackgroundDownloads.channel,
  }) : _repo = repository;

  /// Channel implemented in `DownloadsChannel.kt`.
  static const channel = MethodChannel('io.github.infvyr.ftube/downloads');

  static const throttle = Duration(seconds: 1);

  final DownloadRepository _repo;
  final AppLocalizations Function() _l10n;
  final NotificationPermission? _notifications;
  final MethodChannel _channel;

  StreamSubscription<List<DownloadJob>>? _sub;

  /// Last known status of every job seen active in this session. Jobs
  /// removed from the queue keep their last status.
  final _session = <String, JobStatus>{};

  Timer? _cooldown;
  BackgroundSummary? _pending;

  bool get active => _session.isNotEmpty;

  void start() {
    _channel.setMethodCallHandler(_onCall);
    _sub = _repo.changes.listen(_onJobs);
  }

  Future<void> dispose() async {
    _cooldown?.cancel();
    _channel.setMethodCallHandler(null);
    await _sub?.cancel();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'cancelAll':
        final ids = [
          for (final j in _repo.jobs)
            if (j.status.isActive || j.status.canResume) j.id,
        ];
        await Future.wait(ids.map(_repo.cancel));
      case 'pauseAll':
        await _repo.pauseAll();
      case 'resumeAll':
        // Kotlin started the service for this; with nothing to resume it
        // must stop again.
        if (_repo.jobs.any((j) => j.status.canResume)) {
          _repo.resumeAll();
        } else {
          _stop();
        }
      default:
        throw MissingPluginException(call.method);
    }
    return null;
  }

  void _onJobs(List<DownloadJob> jobs) {
    final activeJobs = jobs.where((j) => j.status.isActive).toList();
    if (_session.isEmpty) {
      if (activeJobs.isEmpty) return;
      unawaited(_notifications?.requestOnce());
    }
    for (final j in jobs) {
      if (j.status.isActive || _session.containsKey(j.id)) {
        _session[j.id] = j.status;
      }
    }
    if (activeJobs.isEmpty) {
      final paused = jobs.where((j) => j.status.canResume).toList();
      paused.isEmpty ? _stop() : _paused(paused);
      return;
    }
    _pending = summarize(_session, activeJobs);
    _flush();
  }

  /// The notification summary for a session and its active jobs.
  static BackgroundSummary summarize(
    Map<String, JobStatus> session,
    List<DownloadJob> active,
  ) {
    final total = session.length;
    final done = session.values
        .where((s) => !s.isActive && s != JobStatus.paused)
        .length;
    final running = active.where((j) => j.status == JobStatus.running);
    final fractions = running
        .map((j) => j.progress?.fraction)
        .whereType<double>()
        .toList();
    return BackgroundSummary(
      current: min(done + 1, total),
      total: total,
      percent: fractions.isEmpty
          ? null
          : (fractions.reduce((a, b) => a + b) / fractions.length * 100)
                .round(),
      title: (running.firstOrNull ?? active.first).title,
    );
  }

  void _flush() {
    if (_cooldown != null) return;
    final s = _pending;
    if (s == null) return;
    _pending = null;
    _send(s);
    _cooldown = Timer(throttle, () {
      _cooldown = null;
      _flush();
    });
  }

  void _send(BackgroundSummary s) {
    final l10n = _l10n();
    _invoke('update', {
      'title': s.percent == null
          ? l10n.bgProgress(s.current, s.total)
          : l10n.bgProgressPercent(s.current, s.total, s.percent!),
      'text': s.title,
      'percent': s.percent,
      'strings': {
        'progressChannel': l10n.bgChannelProgress,
        'resultChannel': l10n.bgChannelResult,
        'cancelAll': l10n.bgCancelAll,
        'pauseAll': l10n.bgPauseAll,
        'resumeAll': l10n.bgResumeAll,
        'timedOut': l10n.bgTimedOut,
      },
    });
  }

  /// Only paused jobs are left: the service stops, the session goes on.
  void _paused(List<DownloadJob> paused) {
    _cooldown?.cancel();
    _cooldown = null;
    _pending = null;
    _invoke('paused', {
      'title': _l10n().bgPaused(paused.length),
      'text': paused.first.title,
    });
  }

  void _stop() {
    final completed = _session.values
        .where((s) => s == JobStatus.completed)
        .length;
    final failed = _session.values.where((s) => s == JobStatus.failed).length;
    _session.clear();
    _cooldown?.cancel();
    _cooldown = null;
    _pending = null;
    final l10n = _l10n();
    _invoke('stop', {
      'title': completed > 0
          ? l10n.bgFinished(completed)
          : failed > 0
          ? l10n.bgFailed(failed)
          : null,
      'text': completed > 0 && failed > 0 ? l10n.bgFailed(failed) : null,
    });
  }

  void _invoke(String method, Map<String, Object?> args) {
    unawaited(
      _channel.invokeMethod<void>(method, args).catchError((Object _) {
        // The service is best effort: downloads run either way.
      }),
    );
  }
}
