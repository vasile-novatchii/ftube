import 'dart:async';

import 'package:ftube/data/services/process_runner.dart';
import 'package:mocktail/mocktail.dart';

class MockProcessRunner extends Mock implements ProcessRunner {}

/// A [RunningProcess] driven by the test.
class FakeProcess implements RunningProcess {
  final _out = StreamController<String>();
  final _err = StreamController<String>();
  final _exit = Completer<int>();
  int killCount = 0;

  /// Exit code used when the process is killed.
  static const killedExitCode = -15;

  @override
  Stream<String> get stdoutLines => _out.stream;

  @override
  Stream<String> get stderrLines => _err.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void out(String line) => _out.add(line);

  void err(String line) => _err.add(line);

  /// Closes the output and exits with [code]. Ignored after the first call.
  Future<void> finish(int code) async {
    if (_exit.isCompleted) return;
    // close() only completes once a listener drains the stream, so don't
    // await it: a cancelled job may never listen.
    unawaited(_out.close());
    unawaited(_err.close());
    _exit.complete(code);
  }

  @override
  Future<void> kill() async {
    killCount++;
    await finish(killedExitCode);
  }
}
