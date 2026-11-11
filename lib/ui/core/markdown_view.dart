import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/providers.dart';

/// Renders Markdown in the app theme (docs/spec-v0.6.md D-99). Text is
/// selectable, https links open in the browser, and images are not loaded.
class MarkdownView extends ConsumerWidget {
  const MarkdownView(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MarkdownBody(
    data: data,
    selectable: true,
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
    imageBuilder: (uri, title, alt) => Text(alt ?? title ?? ''),
    onTapLink: (text, href, title) {
      final url = href == null ? null : Uri.tryParse(href);
      if (url == null || !url.isScheme('https')) return;
      unawaited(
        ref.read(fileSystemServiceProvider).openUrl(url).catchError((_) {}),
      );
    },
  );
}
