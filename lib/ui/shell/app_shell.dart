import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n.dart';
import '../home/widgets/home_view.dart';
import '../library/widgets/library_view.dart';
import '../queue/view_model/queue_view_model.dart';
import '../settings/widgets/settings_view.dart';

/// Home, Library and Settings. A bottom NavigationBar in narrow windows and
/// a NavigationRail from [railMinWidth] up, on every platform (D-21).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// Narrowest window that gets the side rail.
const railMinWidth = 600.0;

/// Pages stop growing at this width and are centered beyond it.
const maxContentWidth = 1000.0;

class _AppShellState extends ConsumerState<AppShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wide = MediaQuery.sizeOf(context).width >= railMinWidth;
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
    final page = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: switch (_index) {
          0 => const HomeView(),
          1 => const LibraryView(),
          _ => const SettingsView(),
        },
      ),
    );
    void select(int i) => setState(() => _index = i);

    if (!wide) {
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
