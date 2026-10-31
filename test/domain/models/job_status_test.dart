import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/models/models.dart';

void main() {
  // Every edge of the job lifecycle diagram in docs/spec.md.
  const allowed = {
    (JobStatus.queued, JobStatus.running),
    (JobStatus.queued, JobStatus.cancelled),
    (JobStatus.running, JobStatus.running),
    (JobStatus.running, JobStatus.completed),
    (JobStatus.running, JobStatus.failed),
    (JobStatus.running, JobStatus.cancelled),
    (JobStatus.failed, JobStatus.queued),
    (JobStatus.cancelled, JobStatus.queued),
  };

  test('only the transitions in the lifecycle diagram are allowed', () {
    for (final from in JobStatus.values) {
      for (final to in JobStatus.values) {
        expect(
          from.canTransitionTo(to),
          allowed.contains((from, to)),
          reason: '$from -> $to',
        );
      }
    }
  });

  test('action flags follow the transitions', () {
    expect(JobStatus.values.where((s) => s.canCancel), [
      JobStatus.queued,
      JobStatus.running,
    ]);
    expect(JobStatus.values.where((s) => s.canRetry), [
      JobStatus.failed,
      JobStatus.cancelled,
    ]);
    expect(JobStatus.values.where((s) => s.canRemove), [
      JobStatus.completed,
      JobStatus.failed,
      JobStatus.cancelled,
    ]);
    expect(JobStatus.values.where((s) => s.isActive), [
      JobStatus.queued,
      JobStatus.running,
    ]);
  });
}
