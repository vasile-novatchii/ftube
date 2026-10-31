import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Output of a process that ran to completion.
class ProcessOutput {
  const ProcessOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// A started process whose output is read line by line.
abstract interface class RunningProcess {
  /// Decoded stdout, split into lines. Single-subscription.
  Stream<String> get stdoutLines;

  /// Decoded stderr, split into lines. Single-subscription.
  Stream<String> get stderrLines;

  Future<int> get exitCode;

  /// Stops the process and its children. Safe to call more than once.
  Future<void> kill();
}

/// Starts external processes. Services depend on this so tests can fake it.
abstract interface class ProcessRunner {
  /// Throws [ProcessException] when [executable] cannot be started.
  Future<RunningProcess> start(String executable, List<String> arguments);

  /// Runs [executable] to completion and collects its output.
  Future<ProcessOutput> run(String executable, List<String> arguments);
}

/// [ProcessRunner] backed by `dart:io`.
///
/// Output is decoded as UTF-8 (yt-dlp is told to write UTF-8 through
/// `PYTHONIOENCODING`), so titles survive on Windows consoles.
class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  static const _env = {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'};
  static const _utf8 = Utf8Codec(allowMalformed: true);

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: _env,
    );
    return _SystemRunningProcess(process);
  }

  @override
  Future<ProcessOutput> run(String executable, List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: _env,
      stdoutEncoding: _utf8,
      stderrEncoding: _utf8,
    );
    return ProcessOutput(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }
}

class _SystemRunningProcess implements RunningProcess {
  _SystemRunningProcess(this._process);

  final Process _process;
  bool _killed = false;

  static Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(SystemProcessRunner._utf8.decoder)
      .transform(const LineSplitter());

  @override
  Stream<String> get stdoutLines => _lines(_process.stdout);

  @override
  Stream<String> get stderrLines => _lines(_process.stderr);

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> kill() async {
    if (_killed) return;
    _killed = true;
    if (Platform.isWindows) {
      // The PyInstaller yt-dlp.exe runs Python in a child process, and
      // yt-dlp runs ffmpeg in another one; kill the whole tree.
      await Process.run('taskkill', ['/PID', '${_process.pid}', '/T', '/F']);
    } else {
      // The PyInstaller bootloader forwards SIGTERM to its child.
      _process.kill();
    }
  }
}
