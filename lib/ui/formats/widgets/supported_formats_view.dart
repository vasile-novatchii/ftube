import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/providers.dart';
import '../../../domain/models/quality_preset.dart';
import '../../core/l10n.dart';
import '../../shell/app_shell.dart' show maxContentWidth;

/// What Ftube downloads, built from the presets so it can't drift from the
/// app (docs/spec-v0.6.md part C). Static: no network, no yt-dlp call.
class SupportedFormatsView extends ConsumerWidget {
  const SupportedFormatsView({super.key});

  /// The containers a video download can end up in (spec-v0.3 D-35).
  static const videoContainers = ['MP4', 'WebM', 'MKV'];

  static final sitesUrl = Uri.parse(
    'https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md',
  );

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SupportedFormatsView()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final video = [
      for (final p in QualityPreset.values)
        if (!p.isAudioOnly && p != QualityPreset.custom) p,
    ];
    final audio = [
      for (final p in QualityPreset.values)
        if (p.isAudioOnly) p,
    ];

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    Widget chips(List<String> labels) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final l in labels) Chip(label: Text(l))],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.formatsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              header(l10n.formatsVideo),
              chips(videoContainers),
              ListTile(subtitle: Text(l10n.formatsVideoHint)),
              header(l10n.formatsQuality),
              chips([for (final p in video) l10n.presetLabel(p)]),
              ListTile(subtitle: Text(l10n.formatsQualityHint)),
              ListTile(
                title: Text(l10n.presetLabel(QualityPreset.custom)),
                subtitle: Text(l10n.formatsCustomHint),
              ),
              header(l10n.formatsAudio),
              for (final p in audio)
                ListTile(
                  key: Key('formats.${p.name}'),
                  title: Text(l10n.presetLabel(p)),
                  subtitle: Text(
                    p.audioTarget == null
                        ? l10n.formatsOriginal
                        : l10n.formatsConverted,
                  ),
                ),
              header(l10n.formatsSites),
              ListTile(title: Text(l10n.formatsYouTube)),
              ListTile(subtitle: Text(l10n.formatsOtherSites)),
              ListTile(
                key: const Key('formats.sites'),
                leading: const Icon(Icons.open_in_new),
                title: Text(l10n.formatsSitesLink),
                onTap: () => unawaited(
                  ref
                      .read(fileSystemServiceProvider)
                      .openUrl(sitesUrl)
                      .catchError((_) {}),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
