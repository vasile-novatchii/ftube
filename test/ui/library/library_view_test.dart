import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftube/data/services/android/storage_permission_service.dart';
import 'package:ftube/domain/exceptions/ftube_exception.dart';
import 'package:ftube/domain/models/models.dart';
import 'package:ftube/ui/library/widgets/library_view.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';
import 'library_fixtures.dart';

void main() {
  late TestEnv env;
  late Disk disk;

  String path(String name) => p.join(downloads, name);
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ThemeMode themeMode = ThemeMode.light,
    bool settle = true,
    void Function()? arrange,
  }) async {
    tester.view
      ..physicalSize = const Size(1000, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    disk = Disk(env.files);
    arrange?.call();
    final container = await env.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localized(
          const LibraryView(),
          locale: locale,
          themeMode: themeMode,
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String name, String file) async {
    await tester.tap(key('library.actions.${path(file)}'));
    await tester.pumpAndSettle();
    await tester.tap(key('library.$name.${path(file)}'));
    // Not pumpAndSettle: a conversion shows an endless progress bar.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('desktop', () {
    setUp(() => env = TestEnv.desktop());

    for (final (locale, themeMode, title, search) in [
      (const Locale('en'), ThemeMode.light, 'Library', 'Search files'),
      (const Locale('ro'), ThemeMode.dark, 'Bibliotecă', 'Caută fișiere'),
      (const Locale('ar'), ThemeMode.light, 'المكتبة', 'البحث في الملفات'),
    ]) {
      testWidgets('lists files in ${locale.languageCode} '
          '${themeMode.name}', (tester) async {
        await pump(tester, locale: locale, themeMode: themeMode);
        expect(find.text(title), findsOneWidget);
        expect(find.text(search), findsOneWidget);
        expect(find.text('a.mp4'), findsOneWidget);
        expect(find.textContaining('30 B · '), findsOneWidget);
        expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
        expect(find.byIcon(Icons.music_note_outlined), findsOneWidget);
        expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
      });
    }

    testWidgets('shows a spinner, then the empty state', (tester) async {
      final dir = env.defaultDir = Completer();
      await pump(
        tester,
        settle: false,
        arrange: () =>
            when(() => env.files.list(any())).thenAnswer((_) async => []),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      dir.complete(downloads);
      await tester.pumpAndSettle();
      expect(find.text('Your downloads will appear here.'), findsOneWidget);
      expect(key('library.menu'), findsNothing);
    });

    testWidgets('searches, filters and sorts', (tester) async {
      await pump(tester);
      await tester.enterText(key('library.search'), 'zzz');
      await tester.pump();
      expect(find.text('No files match.'), findsOneWidget);
      await tester.enterText(key('library.search'), '');
      await tester.tap(key('library.filter.audio'));
      await tester.pumpAndSettle();
      expect(find.text('b.mp3'), findsOneWidget);
      expect(find.text('a.mp4'), findsNothing);
      await tester.tap(key('library.filter.all'));
      await tester.tap(key('library.sort'));
      await tester.pumpAndSettle();
      await tester.tap(key('library.sort.name'));
      await tester.pumpAndSettle();
      final names = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(names, ['a.mp4', 'b.mp3', 'c.txt']);
    });

    testWidgets('opens on tap and reveals from the menu', (tester) async {
      when(() => env.files.open(any())).thenAnswer((_) async {});
      when(() => env.files.reveal(any())).thenThrow(const FileError());
      await pump(tester);
      await tester.tap(find.text('a.mp4'));
      await tester.pump();
      verify(() => env.files.open(path('a.mp4'))).called(1);
      await tester.tap(key('library.actions.${path('a.mp4')}'));
      await tester.pumpAndSettle();
      expect(key('library.share.${path('a.mp4')}'), findsNothing);
      expect(key('library.mp3.${path('a.mp4')}'), findsOneWidget);
      await tester.tap(key('library.reveal.${path('a.mp4')}'));
      await tester.pumpAndSettle();
      expect(
        find.text('The file could not be changed or opened.'),
        findsOneWidget,
      );
    });

    testWidgets('deletes after confirming, with Undo', (tester) async {
      await pump(tester);
      await action(tester, 'delete', 'a.mp4');
      expect(find.text('Delete a.mp4?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('a.mp4'), findsOneWidget);

      await action(tester, 'delete', 'a.mp4');
      await tester.tap(key('library.confirmDelete'));
      await tester.pump();
      expect(find.text('a.mp4'), findsNothing);
      expect(find.text('File moved to the bin.'), findsOneWidget);
      String seconds() => tester.widget<Text>(key('library.undoSeconds')).data!;
      expect(seconds(), '5');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(seconds(), '4');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('a.mp4'), findsOneWidget);
      verifyNever(() => env.files.trash(any()));

      await action(tester, 'delete', 'a.mp4');
      await tester.tap(key('library.confirmDelete'));
      await tester.pump();
      // Let the SnackBar slide in, which starts its own timer.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      verify(() => env.files.trash([path('a.mp4')])).called(1);
      await tester.pumpAndSettle();
      expect(find.text('File moved to the bin.'), findsNothing);
      expect(find.text('a.mp4'), findsNothing);
      expect(disk.items, hasLength(2));
    });

    testWidgets('selects several files and deletes them', (tester) async {
      await pump(tester);
      await tester.longPress(find.text('a.mp4'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('b.mp3'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(key('library.selectAll'));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(key('library.check.${path('c.txt')}'));
      await tester.pump();
      await tester.tap(key('library.deleteSelected'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files?'), findsOneWidget);
      await tester.tap(key('library.confirmDelete'));
      await tester.pump();
      expect(find.text('2 files moved to the bin.'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('c.txt'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(disk.items.keys, [path('c.txt')]);

      await tester.longPress(find.text('c.txt'));
      await tester.pump();
      await tester.tap(key('library.clearSelection'));
      await tester.pump();
      expect(find.text('Library'), findsOneWidget);
    });

    testWidgets('deletes all after confirming', (tester) async {
      await pump(tester, locale: const Locale('ro'));
      await tester.tap(key('library.menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('library.deleteAll'));
      await tester.pumpAndSettle();
      expect(find.text('Ștergi 3 fișiere?'), findsOneWidget);
      await tester.tap(key('library.confirmDelete'));
      await tester.pump();
      expect(find.text('3 fișiere mutate în coș.'), findsOneWidget);
      expect(find.text('Your downloads will appear here.'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(disk.items, isEmpty);
    });

    testWidgets('renames, showing errors in the dialog', (tester) async {
      await pump(tester);
      await action(tester, 'rename', 'a.mp4');
      final field = key('library.renameField');
      expect(tester.widget<TextField>(field).controller!.text, 'a');
      expect(find.text('.mp4'), findsOneWidget);
      await tester.enterText(field, 'b/c');
      await tester.tap(key('library.renameSave'));
      await tester.pumpAndSettle();
      expect(find.text("That name can't be used for a file."), findsOneWidget);
      await tester.enterText(field, 'song');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(find.text('song.mp4'), findsOneWidget);

      await action(tester, 'rename', 'c.txt');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('c.txt'), findsOneWidget);
    });

    testWidgets('converts with progress and can stop', (tester) async {
      final run = StreamController<JobProgress>();
      addTearDown(run.close);
      env.media.onConvert = (_, _) => run.stream;
      await pump(tester);
      await action(tester, 'ogg', 'a.mp4');
      expect(find.text('Converting...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(key('library.stop.${path('a.mp4')}'));
      await tester.pump();
      expect(find.text('Converting...'), findsNothing);
      expect(env.media.cancelled, hasLength(1));
    });

    testWidgets('says where a conversion was saved', (tester) async {
      await pump(tester);
      await action(tester, 'mp3', 'a.mp4');
      expect(find.text('Saved as a.mp3.'), findsOneWidget);
    });

    testWidgets('a listing error offers Retry', (tester) async {
      await pump(
        tester,
        arrange: () =>
            when(() => env.files.list(any())).thenThrow(const FileError()),
      );
      expect(
        find.text('The file could not be changed or opened.'),
        findsOneWidget,
      );
      disk.stub();
      await tester.tap(key('library.retry'));
      await tester.pumpAndSettle();
      expect(find.text('a.mp4'), findsOneWidget);
    });

    testWidgets('no folder is explained', (tester) async {
      env.defaultDir = Completer()..complete(null);
      await pump(tester);
      expect(find.text('The download folder is not available.'), findsOne);
    });
  });

  group('android', () {
    setUp(() => env = TestEnv.android());

    testWidgets('shares from the menu, with no reveal', (tester) async {
      when(() => env.files.share(any())).thenAnswer((_) async {});
      await pump(tester);
      await tester.tap(key('library.actions.${path('b.mp3')}'));
      await tester.pumpAndSettle();
      expect(key('library.reveal.${path('b.mp3')}'), findsNothing);
      expect(key('library.mp3.${path('b.mp3')}'), findsNothing);
      await tester.tap(key('library.share.${path('b.mp3')}'));
      await tester.pumpAndSettle();
      verify(() => env.files.share(path('b.mp3'))).called(1);
    });

    testWidgets('blocked storage offers to grant access', (tester) async {
      when(env.storage.ensureGranted).thenThrow(const StoragePermission());
      when(() => env.storage.request())
          .thenAnswer((_) async => StorageAccess.granted);
      await pump(tester);
      expect(
        find.text('Ftube needs All files access to save downloads.'),
        findsOneWidget,
      );
      when(env.storage.ensureGranted).thenAnswer((_) async {});
      await tester.tap(key('library.grant'));
      await tester.pumpAndSettle();
      expect(find.text('a.mp4'), findsOneWidget);
    });
  });
}
