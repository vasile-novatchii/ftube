/// A published Ftube release on GitHub (docs/spec-v0.6.md A2).
final class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.pageUrl,
    required this.notes,
    this.publishedAt,
  });

  /// The tag without its leading `v`, for example `0.6.0`.
  final String version;

  /// The git tag, for example `v0.6.0`.
  final String tag;

  /// The release page the user downloads from.
  final Uri pageUrl;

  final DateTime? publishedAt;

  /// Release notes as Markdown; empty when there are none.
  final String notes;
}

/// The result of one update check.
sealed class UpdateCheck {
  const UpdateCheck();
}

final class UpToDate extends UpdateCheck {
  const UpToDate(this.current);

  final String current;
}

final class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.current, this.release);

  final String current;
  final AppRelease release;
}

/// Offline, rate-limited or an unexpected reply (DoD-58).
final class CheckFailed extends UpdateCheck {
  const CheckFailed(this.reason);

  final String reason;
}
