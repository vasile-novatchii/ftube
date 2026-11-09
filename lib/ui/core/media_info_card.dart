import 'package:flutter/material.dart';

import '../../domain/models/models.dart';
import 'l10n.dart';

/// Thumbnail, title, uploader and length of a fetched video.
class MediaInfoCard extends StatelessWidget {
  const MediaInfoCard({required this.info, this.titleKey, super.key});

  final MediaInfo info;

  /// Key of the title text, for tests.
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      ?info.uploader,
      if (info.duration case final d?) formatDuration(d),
    ].join(' · ');
    final placeholder = Container(
      width: 120,
      height: 68,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.movie_outlined),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: switch (info.thumbnailUrl) {
            final url? => Image.network(
              url,
              width: 120,
              height: 68,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
            null => placeholder,
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.title,
                key: titleKey,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
