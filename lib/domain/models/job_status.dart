/// Lifecycle of a download job, see the state diagram in docs/spec.md.
enum JobStatus {
  queued,
  running,
  completed,
  failed,
  cancelled;

  static const _transitions = <JobStatus, Set<JobStatus>>{
    queued: {running, cancelled},
    running: {running, completed, failed, cancelled},
    completed: {},
    failed: {queued},
    cancelled: {queued},
  };

  bool canTransitionTo(JobStatus next) => _transitions[this]!.contains(next);

  bool get isActive => this == queued || this == running;

  bool get canCancel => canTransitionTo(cancelled);

  bool get canRetry => canTransitionTo(queued);

  /// Completed, failed and cancelled jobs can be removed from the queue.
  bool get canRemove => !isActive;
}
