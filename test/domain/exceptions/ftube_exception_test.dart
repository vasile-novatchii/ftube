import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';

void main() {
  test('every failure is an FtubeException and an Exception', () {
    const all = <FtubeException>[
      InvalidUrl(),
      Unsupported(),
      Network(),
      BinaryMissing('yt-dlp'),
      ChecksumMismatch('ffmpeg'),
      ProcessFailed(1, ''),
      StoragePermission(),
      Cancelled(),
    ];
    for (final e in all) {
      expect(e, isA<Exception>());
    }
  });

  test('toString includes the detail when present', () {
    expect(const Network().toString(), 'Network');
    expect(const Network('timeout').toString(), 'Network: timeout');
    expect(const BinaryMissing('ffmpeg').toString(), 'BinaryMissing: ffmpeg');
    expect(const ProcessFailed(2, 'x').toString(), 'ProcessFailed: exit 2');
  });

  group('ProcessFailed.fromStderr', () {
    test('keeps the last non-empty lines', () {
      final stderr = List.generate(30, (i) => 'line $i').join('\n');
      final e = ProcessFailed.fromStderr(1, '$stderr\n\n');
      expect(e.exitCode, 1);
      final lines = e.stderrTail.split('\n');
      expect(lines, hasLength(20));
      expect(lines.first, 'line 10');
      expect(lines.last, 'line 29');
    });

    test('handles CRLF, blank lines and a custom limit', () {
      final e = ProcessFailed.fromStderr(
        3,
        'a\r\n\r\nb\r\n  \r\nc\r\n',
        maxLines: 2,
      );
      expect(e.stderrTail, 'b\nc');
    });

    test('empty stderr gives an empty tail', () {
      expect(ProcessFailed.fromStderr(1, '').stderrTail, isEmpty);
    });
  });
}
