/// Lifecycle of a download job, see the state diagram in docs/spec.md.
enum JobStatus {
  queued,
  running,
  completed,
  failed,
  cancelled,

  /// Stopped by the user with its partial files kept (spec-v0.4 D-67).
  paused;

  static const _transitions = <JobStatus, Set<JobStatus>>{
    queued: {running, cancelled, paused},
    running: {running, completed, failed, cancelled, paused},
    completed: {},
    failed: {queued},
    cancelled: {queued},
    paused: {queued, cancelled},
  };

  bool canTransitionTo(JobStatus next) => _transitions[this]!.contains(next);

  bool get isActive => this == queued || this == running;

  bool get canCancel => canTransitionTo(cancelled);

  bool get canRetry => this == failed || this == cancelled;

  bool get canPause => isActive;

  bool get canResume => this == paused;

  /// Completed, failed, cancelled and paused jobs can be removed from the
  /// queue.
  bool get canRemove => !isActive;
}
