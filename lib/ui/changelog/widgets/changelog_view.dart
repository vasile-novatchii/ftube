import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/markdown_view.dart';
import '../../shell/app_shell.dart' show maxContentWidth;

/// The bundled CHANGELOG.md, opened from Settings > App version
/// (docs/spec-v0.6.md D-98, D-100). The text is English only.
class ChangelogView extends StatefulWidget {
  const ChangelogView({super.key});

  static const asset = 'CHANGELOG.md';

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ChangelogView()));

  @override
  State<ChangelogView> createState() => _ChangelogViewState();
}

class _ChangelogViewState extends State<ChangelogView> {
  Future<String>? _text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _text ??= DefaultAssetBundle.of(context)
        .loadString(ChangelogView.asset)
        // The app bar already says "Changelog".
        .then((s) => s.replaceFirst(RegExp(r'^# .*\n+'), ''));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changelogTitle)),
      body: FutureBuilder(
        future: _text,
        builder: (context, snapshot) => switch (snapshot) {
          AsyncSnapshot(:final String data) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxContentWidth),
                child: MarkdownView(data, key: const Key('changelog.text')),
              ),
            ),
          ),
          AsyncSnapshot(hasError: true) => Center(
            child: Text(l10n.updateNoNotes),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}
