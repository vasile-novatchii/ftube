import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/android/storage_permission_service.dart';
import '../../../domain/models/app_settings.dart';
import '../../../domain/models/quality_preset.dart';
import '../../core/l10n.dart';
import '../../update/widgets/update_widgets.dart';
import '../view_model/settings_view_model.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The user may have changed storage access in system settings.
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          ref.read(settingsViewModelProvider.notifier).refreshStorageAccess(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(settingsViewModelProvider);
    final vm = ref.read(settingsViewModelProvider.notifier);
    ref.listen(settingsViewModelProvider, (prev, next) {
      String? message;
      if (prev?.ytDlpUpdate == UpdateStatus.running) {
        message = switch (next.ytDlpUpdate) {
          UpdateStatus.done => l10n.ytDlpUpdated(next.ytDlpVersion ?? '?'),
          UpdateStatus.failed => l10n.errorMessage(next.ytDlpUpdateError ?? ''),
          _ => null,
        };
      }
      if (prev?.clearData == UpdateStatus.running) {
        message = switch (next.clearData) {
          UpdateStatus.done => l10n.settingsClearDataDone,
          UpdateStatus.failed => l10n.errorMessage(next.clearDataError ?? ''),
          _ => message,
        };
      }
      if (message == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Header(l10n.settingsAppearance),
          _ControlTile(
            title: Text(l10n.settingsTheme),
            control: DropdownButton<ThemePreference>(
              key: const Key('settings.theme'),
              value: settings.theme,
              onChanged: (t) => t == null ? null : vm.setTheme(t),
              items: [
                for (final t in ThemePreference.values)
                  DropdownMenuItem(value: t, child: Text(l10n.themeLabel(t))),
              ],
            ),
          ),
          _ControlTile(
            title: Text(l10n.settingsLanguage),
            control: DropdownButton<AppLanguage>(
              key: const Key('settings.language'),
              value: settings.language,
              onChanged: (lang) => lang == null ? null : vm.setLanguage(lang),
              items: [
                for (final lang in AppLanguage.values)
                  DropdownMenuItem(
                    value: lang,
                    child: Text(l10n.languageLabel(lang)),
                  ),
              ],
            ),
          ),
          _Header(l10n.settingsDownloads),
          ListTile(
            key: const Key('settings.folder'),
            title: Text(l10n.settingsDownloadFolder),
            subtitle: Text(state.downloadDir ?? '...'),
          ),
          if (state.canChangeDownloadDir || !state.usesDefaultDir)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  if (state.canChangeDownloadDir)
                    OutlinedButton(
                      key: const Key('settings.folder.change'),
                      onPressed: vm.pickDownloadDir,
                      child: Text(l10n.settingsDownloadFolderChange),
                    ),
                  if (!state.usesDefaultDir)
                    TextButton(
                      key: const Key('settings.folder.reset'),
                      onPressed: vm.resetDownloadDir,
                      child: Text(l10n.settingsDownloadFolderReset),
                    ),
                ],
              ),
            ),
          _ControlTile(
            title: Text(l10n.settingsDefaultQuality),
            control: DropdownButton<QualityPreset>(
              key: const Key('settings.preset'),
              value: settings.defaultPreset,
              onChanged: (p) => p == null ? null : vm.setDefaultPreset(p),
              items: [
                for (final p in defaultPresetChoices)
                  DropdownMenuItem(value: p, child: Text(l10n.presetLabel(p))),
              ],
            ),
          ),
          ListTile(title: Text(l10n.settingsConcurrentDownloads)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              key: const Key('settings.concurrent'),
              segments: [
                for (
                  var n = AppSettings.minConcurrent;
                  n <= AppSettings.maxConcurrent;
                  n++
                )
                  ButtonSegment(
                    value: n,
                    label: Text(l10n.settingsConcurrentDownloadsValue(n)),
                  ),
              ],
              selected: {settings.concurrentDownloads},
              onSelectionChanged: (s) => vm.setConcurrentDownloads(s.first),
            ),
          ),
          if (state.storageAccess case final access?) ...[
            _Header(l10n.settingsStorageAccess),
            _ControlTile(
              key: const Key('settings.storage'),
              leading: Icon(
                access == StorageAccess.granted
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
              ),
              title: Text(
                access == StorageAccess.granted
                    ? l10n.storageGranted
                    : l10n.storageDenied,
              ),
              control: access == StorageAccess.granted
                  ? null
                  : FilledButton(
                      onPressed: vm.requestStorageAccess,
                      child: Text(l10n.storageGrant),
                    ),
            ),
          ],
          _Header(l10n.settingsTools),
          _ControlTile(
            title: Text(l10n.settingsYtDlpVersion),
            subtitle: Text(_version(l10n, state, state.ytDlpVersion)),
            control: state.ytDlpUpdate == UpdateStatus.running
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton(
                    key: const Key('settings.updateYtDlp'),
                    onPressed: vm.updateYtDlp,
                    child: Text(l10n.settingsUpdateYtDlp),
                  ),
          ),
          ListTile(
            title: Text(l10n.settingsFfmpegVersion),
            subtitle: Text(_version(l10n, state, state.ffmpegVersion)),
          ),
          _Header(l10n.settingsData),
          ListTile(
            key: const Key('settings.clearData'),
            enabled: state.canClearData,
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(l10n.settingsClearData),
            subtitle: Text(
              state.downloading
                  ? l10n.settingsClearDataBusy
                  : l10n.settingsClearDataHint,
            ),
            onTap: () => _confirmClearData(vm),
          ),
          _Header(l10n.settingsAbout),
          ListTile(
            title: Text(l10n.settingsAppVersion),
            subtitle: Text(state.appVersion ?? '...'),
          ),
          const UpdateCheckTile(),
          ListTile(
            title: Text(l10n.settingsLicense),
            subtitle: Text(l10n.licenseGpl),
          ),
          ListTile(
            key: const Key('settings.licenses'),
            title: Text(l10n.settingsThirdParty),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: state.appVersion,
              applicationLegalese: l10n.licenseGpl,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearData(SettingsViewModel vm) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsClearDataTitle),
        content: Text(l10n.settingsClearDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('settings.confirmClearData'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsClearDataConfirm),
          ),
        ],
      ),
    );
    if (ok ?? false) await vm.clearAppData();
  }

  static String _version(
    AppLocalizations l10n,
    SettingsState state,
    String? version,
  ) =>
      version ??
      (state.loadingVersions ? l10n.versionLoading : l10n.versionUnknown);
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// A setting with a control at the end of the row. On a narrow screen the
/// control moves under the title, so long translations still fit (D-30).
class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.title,
    required this.control,
    this.leading,
    this.subtitle,
    super.key,
  });

  /// Below this width the control goes under the title.
  static const stackBelow = 480.0;

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? control;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (control == null || constraints.maxWidth >= stackBelow) {
        return ListTile(
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: control,
        );
      }
      return ListTile(
        leading: leading,
        title: title,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?subtitle,
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              // In a tiny pop-up window even a whole row may be too short.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: control,
              ),
            ),
          ],
        ),
      );
    },
  );
}
