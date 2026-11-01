// Downloads one short video as MP3 with the installed desktop binaries,
// the way the app does (docs/spec.md section 6, smoke row).
//
//   dart run tool/smoke_download.dart [--dir <bin dir>] [--url <url>]
//
// --dir defaults to build/installed (see tool/install_binaries.dart).
// --url defaults to a 19-second public YouTube video.
import 'dart:io';

import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/data/services/desktop/desktop_media_service.dart';
import 'package:ftube/data/services/process_runner.dart';
import 'package:ftube/domain/models/models.dart';

const _defaultUrl = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } on Object catch (e) {
    stderr.writeln('smoke_download: $e');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final os = DesktopOs.current ?? (throw UnsupportedError('not a desktop OS'));
  final binDir = Directory(option('--dir') ?? 'build/installed');
  final url = option('--url') ?? _defaultUrl;
  final work = await Directory.systemTemp.createTemp('ftube_smoke');
  try {
    const runner = SystemProcessRunner();
    final media = DesktopMediaService(
      binaries: BinaryService(os: os, binDir: binDir, runner: runner),
      runner: runner,
      tempRoot: Directory('${work.path}/tmp'),
    );
    final info = await media.fetchInfo(url);
    stdout.writeln('Title: ${info.title}');

    String? output;
    await for (final progress in media.download(
      DownloadRequest(
        jobId: 'smoke',
        url: url,
        preset: QualityPreset.audioMp3,
        outDir: Directory('${work.path}/out'),
      ),
    )) {
      if (progress.phase == JobPhase.finished) output = progress.outputPath;
    }
    final file = File(output ?? (throw StateError('no output file')));
    final size = await file.length();
    if (size == 0) throw StateError('${file.path} is empty');
    stdout.writeln('Saved ${file.uri.pathSegments.last} ($size bytes)');
  } finally {
    await work.delete(recursive: true);
  }
}
