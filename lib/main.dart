import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/licenses.dart';
import 'config/providers.dart';
import 'data/services/binaries/binary_catalog.dart';
import 'data/services/prefs_service.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  final platform = AppPlatform.current;
  final (prefs, dirs) = await (PrefsService.load(), AppDirs.resolve()).wait;
  final catalog = platform.isDesktop
      ? BinaryCatalog.parse(
          await rootBundle.loadString('assets/binaries/catalog.json'),
        )
      : null;
  runApp(
    ProviderScope(
      overrides: [
        prefsServiceProvider.overrideWithValue(prefs),
        appDirsProvider.overrideWithValue(dirs),
        if (catalog != null) binaryCatalogProvider.overrideWithValue(catalog),
      ],
      child: const FtubeApp(),
    ),
  );
}
