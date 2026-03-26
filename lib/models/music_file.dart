class MusicFile {
  const MusicFile({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.displayName,
    required this.path,
    required this.uri,
    required this.durationMs,
  });

  factory MusicFile.fromMap(Map<dynamic, dynamic> map) {
    String valueOf(String key, {String fallback = ''}) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
      return fallback;
    }

    int intOf(String key) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    return MusicFile(
      id: valueOf('id'),
      title: valueOf('title', fallback: 'Unknown title'),
      artist: valueOf('artist', fallback: 'Unknown artist'),
      album: valueOf('album', fallback: 'Unknown album'),
      displayName: valueOf('displayName'),
      path: valueOf('path'),
      uri: valueOf('uri'),
      durationMs: intOf('durationMs'),
    );
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final String displayName;
  final String path;
  final String uri;
  final int durationMs;

  String get pathLabel {
    if (path.isNotEmpty) {
      return path;
    }
    if (displayName.isNotEmpty) {
      return displayName;
    }
    if (uri.isNotEmpty) {
      return uri;
    }
    return id;
  }

  String get normalizedPath => path.replaceAll('\\', '/').trim();

  String get folderPath {
    final sourcePath = normalizedPath;
    if (sourcePath.isEmpty) {
      return '';
    }

    final trimmedPath = sourcePath.endsWith('/')
        ? sourcePath.substring(0, sourcePath.length - 1)
        : sourcePath;
    final lastSlashIndex = trimmedPath.lastIndexOf('/');
    if (lastSlashIndex <= 0) {
      return '';
    }
    return trimmedPath.substring(0, lastSlashIndex);
  }

  String get folderName {
    final sourceFolderPath = folderPath;
    if (sourceFolderPath.isEmpty) {
      return 'Unknown folder';
    }

    final lastSlashIndex = sourceFolderPath.lastIndexOf('/');
    if (lastSlashIndex < 0 || lastSlashIndex == sourceFolderPath.length - 1) {
      return sourceFolderPath;
    }

    return sourceFolderPath.substring(lastSlashIndex + 1);
  }
}
