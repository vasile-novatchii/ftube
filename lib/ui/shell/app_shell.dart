import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/providers.dart';
import '../core/l10n.dart';
import '../home/widgets/home_view.dart';
import '../queue/view_model/queue_view_model.dart';
import '../settings/widgets/settings_view.dart';

/// Home, Library and Settings. NavigationBar on Android, NavigationRail on
/// desktop.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final desktop = ref.watch(appPlatformProvider).isDesktop;
    final destinations = [
      (Icons.home_outlined, Icons.home, l10n.navHome),
      (Icons.video_library_outlined, Icons.video_library, l10n.navLibrary),
      (Icons.settings_outlined, Icons.settings, l10n.navSettings),
    ];
    final active = ref.watch(activeDownloadCountProvider);
    Widget badged(IconData icon) => Badge(
      isLabelVisible: active > 0,
      label: Text('$active'),
      child: Icon(icon),
    );
    // Library gets its own View in P8.
    final page = switch (_index) {
      0 => const HomeView(),
      1 => _Placeholder(title: l10n.navLibrary, text: l10n.libraryEmpty),
      _ => const SettingsView(),
    };
    void select(int i) => setState(() => _index = i);

    if (!desktop) {
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: select,
          destinations: [
            for (final (icon, selected, label) in destinations)
              NavigationDestination(
                icon: icon == Icons.home_outlined ? badged(icon) : Icon(icon),
                selectedIcon: icon == Icons.home_outlined
                    ? badged(selected)
                    : Icon(selected),
                label: label,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final (icon, selected, label) in destinations)
                NavigationRailDestination(
                  icon: icon == Icons.home_outlined ? badged(icon) : Icon(icon),
                  selectedIcon: icon == Icons.home_outlined
                      ? badged(selected)
                      : Icon(selected),
                  label: Text(label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    ),
  );
}
