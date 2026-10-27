// @dart=2.10
class MediaTrack {
  final String id, name, url, path;
  final bool video;
  const MediaTrack(
      {this.id, this.name, this.url, this.path, this.video = false});
}

class MediaQueue {
  static List<MediaTrack> from(List<MediaTrack> source, MediaTrack selected,
      {bool continuous = false}) {
    if (!continuous) return [selected];
    final items = source.where((item) => item.video == selected.video).toList();
    final index = items.indexWhere((item) => item.id == selected.id);
    return index < 0 ? [selected] : items.sublist(index);
  }
}
