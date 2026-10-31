import '../../domain/models/job_progress.dart';

/// Maps a per-phase fraction to the overall job fraction.
///
/// Video jobs: video 0-80%, audio 80-95%, merge 95-100%.
/// Audio-only jobs: audio download 0-90%, conversion 90-100%.
/// Conversions of a local file use the whole 0-100% for [JobPhase.converting].
abstract final class ProgressWeights {
  static double overall(
    JobPhase phase,
    double phaseFraction, {
    required bool audioOnly,
    bool conversionOnly = false,
  }) {
    final f = phaseFraction.clamp(0.0, 1.0);
    final (start, end) = switch (phase) {
      JobPhase.finished => (1.0, 1.0),
      JobPhase.converting when conversionOnly => (0.0, 1.0),
      JobPhase.converting => (0.9, 1.0),
      JobPhase.downloadingAudio when audioOnly => (0.0, 0.9),
      JobPhase.downloadingAudio => (0.8, 0.95),
      JobPhase.downloadingVideo => (0.0, 0.8),
      JobPhase.merging => (0.95, 1.0),
    };
    return start + (end - start) * f;
  }
}
