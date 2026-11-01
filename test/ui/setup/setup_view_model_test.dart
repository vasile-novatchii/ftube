import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/binaries/binary_installer.dart';
import 'package:ftube/data/services/binary_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/ui/setup/view_model/setup_view_model.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late ProviderContainer container;

  SetupState state() => container.read(setupViewModelProvider);
  SetupViewModel vm() => container.read(setupViewModelProvider.notifier);

  Future<void> start() async {
    container = await env.container();
    container.read(setupViewModelProvider);
    await pumpEventQueue();
  }

  const progress = InstallProgress(
    binary: Binary.ffmpeg,
    phase: InstallPhase.downloading,
    receivedBytes: 10,
    totalBytes: 30,
  );

  test('is ready on Android without checking anything', () async {
    env = TestEnv.android();
    await start();
    expect(state(), const SetupState.ready());
    await vm().check();
    vm().install();
    await vm().cancel();
    expect(state(), const SetupState.ready());
  });

  group('desktop', () {
    setUp(() => env = TestEnv.desktop());

    test('is ready when nothing is missing', () async {
      env.installer;
      container = await env.container();
      expect(container.read(setupViewModelProvider), isA<SetupChecking>());
      await pumpEventQueue();
      expect(state(), const SetupState.ready());
    });

    test('reports the size of what is missing', () async {
      when(() => env.installer.missing()).thenAnswer(
        (_) async => [entry(Binary.ffmpeg, 20), entry(Binary.deno, 10)],
      );
      await start();
      expect(state(), const SetupState.needed(totalBytes: 30));
    });

    test('fails when the check throws, and retries', () async {
      when(() => env.installer.missing())
          .thenThrow(const Unsupported('no binaries'));
      await start();
      expect(state(), isA<SetupFailed>());
      expect((state() as SetupFailed).error, isA<Unsupported>());

      when(() => env.installer.missing()).thenAnswer((_) async => []);
      await vm().check();
      expect(state(), const SetupState.ready());
    });

    test('install reports progress, then checks again', () async {
      final events = StreamController<InstallProgress>();
      when(() => env.installer.missing())
          .thenAnswer((_) async => [entry(Binary.ffmpeg, 30)]);
      when(() => env.installer.install()).thenAnswer((_) => events.stream);
      await start();

      vm().install();
      expect(state(), const SetupState.installing());
      vm().install(); // ignored while installing
      events.add(progress);
      await pumpEventQueue();
      expect(state(), const SetupState.installing(progress: progress));

      when(() => env.installer.missing()).thenAnswer((_) async => []);
      await events.close();
      await pumpEventQueue();
      expect(state(), const SetupState.ready());
      verify(() => env.installer.install()).called(1);
    });

    test('install errors fail the setup', () async {
      when(() => env.installer.missing())
          .thenAnswer((_) async => [entry(Binary.ffmpeg, 30)]);
      when(() => env.installer.install())
          .thenAnswer((_) => Stream.error(const ChecksumMismatch('ffmpeg')));
      await start();
      vm().install();
      await pumpEventQueue();
      expect((state() as SetupFailed).error, isA<ChecksumMismatch>());
    });

    test('cancel stops the download and checks again', () async {
      final events = StreamController<InstallProgress>();
      when(() => env.installer.missing())
          .thenAnswer((_) async => [entry(Binary.ffmpeg, 30)]);
      when(() => env.installer.install()).thenAnswer((_) => events.stream);
      await start();
      vm().install();
      await pumpEventQueue();
      expect(events.hasListener, isTrue);

      await vm().cancel();
      expect(events.hasListener, isFalse);
      expect(state(), const SetupState.needed(totalBytes: 30));
      await vm().cancel(); // nothing to cancel
      await events.close();
    });

    test('disposing the container stops the download', () async {
      final events = StreamController<InstallProgress>();
      when(() => env.installer.missing())
          .thenAnswer((_) async => [entry(Binary.ffmpeg, 30)]);
      when(() => env.installer.install()).thenAnswer((_) => events.stream);
      await start();
      vm().install();
      await pumpEventQueue();
      container.dispose();
      await pumpEventQueue();
      expect(events.hasListener, isFalse);
      await events.close();
    });
  });
}
