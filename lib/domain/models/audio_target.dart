/// Audio formats Ftube can extract or convert to.
enum AudioTarget {
  mp3('mp3'),
  ogg('ogg');

  const AudioTarget(this.extension);

  /// File extension without the dot.
  final String extension;
}
