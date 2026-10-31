import 'package:freezed_annotation/freezed_annotation.dart';

part 'library_item.freezed.dart';

/// Media type of a file in the library, used for icons and filtering.
enum LibraryKind {
  video,
  audio,
  other;

  static const _video = {'mp4', 'mkv', 'webm', 'mov', 'avi', 'flv', '3gp'};
  static const _audio = {'mp3', 'ogg', 'm4a', 'opus', 'aac', 'flac', 'wav'};

  static LibraryKind fromPath(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return other;
    final ext = name.substring(dot + 1).toLowerCase();
    if (_video.contains(ext)) return video;
    if (_audio.contains(ext)) return audio;
    return other;
  }
}

/// A file in the download folder.
@freezed
abstract class LibraryItem with _$LibraryItem {
  const factory LibraryItem({
    required String path,
    required String name,
    required int sizeBytes,
    required DateTime modified,
    required LibraryKind kind,
  }) = _LibraryItem;
}
