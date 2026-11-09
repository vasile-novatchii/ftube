import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/models.dart';
import '../../core/l10n.dart';
import '../../core/media_info_card.dart';
import '../../queue/widgets/queue_view.dart';
import '../view_model/home_view_model.dart';

/// Paste a link, see its info, pick a quality and download. The queue sits
/// below.
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  final _url = TextEditingController();
  late final AppLifecycleListener _lifecycle;

  HomeViewModel get _vm => ref.read(homeViewModelProvider.notifier);

  @override
  void initState() {
    super.initState();
    _url.text = ref.read(homeViewModelProvider).url;
    _lifecycle = AppLifecycleListener(
      onResume: () {
        unawaited(_vm.checkClipboard());
        unawaited(_vm.refreshStorageAccess());
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_vm.checkClipboard());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final queued = context.l10n.homeQueued;
    final job = await _vm.download();
    if (job != null) {
      messenger.showSnackBar(SnackBar(content: Text(queued)));
    }
  }

  Future<void> _pickFormat(MediaInfo info, String? selected) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FormatSheet(info: info, selected: selected),
    );
    if (id != null) _vm.selectFormat(id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(homeViewModelProvider);
    if (_url.text != state.url) _url.text = state.url;

    final error = switch (state.error) {
      null => null,
      NoDownloadFolder() => l10n.homeNoFolder,
      final e => l10n.errorMessage(e),
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          if (state.storageBlocked)
            _Banner(
              text: l10n.storageDenied,
              actions: [
                FilledButton(
                  key: const Key('home.grant'),
                  onPressed: _vm.grantStorageAccess,
                  child: Text(l10n.storageGrant),
                ),
              ],
            ),
          if (state.clipboardUrl case final clip?)
            _Banner(
              text: '${l10n.homeClipboardFound}\n$clip',
              actions: [
                TextButton(
                  key: const Key('home.clipboard.dismiss'),
                  onPressed: _vm.dismissClipboard,
                  child: Text(l10n.homeClipboardDismiss),
                ),
                FilledButton(
                  key: const Key('home.clipboard.use'),
                  onPressed: _vm.useClipboard,
                  child: Text(l10n.homeClipboardUse),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('home.url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    hintText: l10n.homeUrlHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: state.url.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('home.clear'),
                            tooltip: l10n.homeClear,
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _url.clear();
                              _vm.setUrl('');
                            },
                          ),
                  ),
                  onChanged: _vm.setUrl,
                  onSubmitted: (_) => _vm.fetch(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('home.paste'),
                tooltip: l10n.homePaste,
                icon: const Icon(Icons.content_paste),
                onPressed: _vm.paste,
              ),
              FilledButton(
                key: const Key('home.fetch'),
                onPressed: state.canFetch ? _vm.fetch : null,
                child: Text(l10n.homeFetch),
              ),
            ],
          ),
          if (state.fetching)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                key: const Key('home.error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (state.url.isEmpty && state.info == null && error == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                l10n.homeEmpty,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (state.info case final info?) ...[
            const SizedBox(height: 16),
            MediaInfoCard(info: info, titleKey: const Key('home.title')),
            const SizedBox(height: 12),
            Text(l10n.homeQuality, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in homePresets)
                  ChoiceChip(
                    key: Key('home.preset.${preset.name}'),
                    label: Text(l10n.presetLabel(preset)),
                    selected: state.preset == preset,
                    onSelected: (_) => _vm.selectPreset(preset),
                  ),
                if (info.formats.isNotEmpty)
                  ChoiceChip(
                    key: const Key('home.formats'),
                    avatar: const Icon(Icons.tune, size: 18),
                    label: Text(
                      state.selectedFormat == null
                          ? l10n.homeAllFormats
                          : l10n.formatLabel(state.selectedFormat!),
                    ),
                    selected: state.preset == QualityPreset.custom,
                    onSelected: (_) => _pickFormat(info, state.formatId),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: const Key('home.download'),
                onPressed: state.canDownload ? _download : null,
                icon: const Icon(Icons.download),
                label: Text(l10n.homeDownload),
              ),
            ),
          ],
          const Divider(height: 32),
          const QueueView(),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: actions),
        ],
      ),
    ),
  );
}

class _FormatSheet extends StatelessWidget {
  const _FormatSheet({required this.info, required this.selected});

  final MediaInfo info;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.homeAllFormats,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final f in info.formats)
            ListTile(
              key: Key('format.${f.id}'),
              leading: Icon(switch (f.kind) {
                FormatKind.audioOnly => Icons.music_note_outlined,
                FormatKind.videoOnly => Icons.videocam_outlined,
                FormatKind.videoAudio => Icons.movie_outlined,
              }),
              title: Text(l10n.formatLabel(f)),
              subtitle: Text(f.id),
              selected: f.id == selected,
              onTap: () => Navigator.pop(context, f.id),
            ),
        ],
      ),
    );
  }
}
