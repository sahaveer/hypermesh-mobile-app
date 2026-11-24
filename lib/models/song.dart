class Song {
  final String id;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final String? coverHash;
  final String ownerId;
  final String ownerName;
  final String sourceNodeName;
  final String sourceNodeHost;
  final bool isPeer;
  bool isFavorite;
  final String? localFilePath;
  final String? demoAsset;
  final String? shareId;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.coverHash,
    required this.ownerId,
    required this.ownerName,
    required this.sourceNodeName,
    required this.sourceNodeHost,
    this.isPeer = false,
    this.isFavorite = false,
    this.localFilePath,
    this.demoAsset,
    this.shareId,
  });

  factory Song.fromJson(
    Map<String, dynamic> json, {
    String sourceNodeName = "My Hub",
    String sourceNodeHost = "",
    bool isPeer = false,
    String? localFilePath,
  }) {
    return Song(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Title',
      artist: json['artist']?.toString() ?? 'Unknown Artist',
      album: json['album']?.toString() ?? 'Unknown Album',
      duration: (json['duration'] is num) ? (json['duration'] as num).toDouble() : 0.0,
      coverHash: json['cover_hash']?.toString(),
      ownerId: json['owner_id']?.toString() ?? 'host',
      ownerName: json['owner_name']?.toString() ?? 'Host',
      sourceNodeName: sourceNodeName,
      sourceNodeHost: sourceNodeHost,
      isPeer: isPeer,
      isFavorite: json['is_favorite'] == 1 || json['is_favorite'] == true,
      localFilePath: localFilePath ?? json['local_file_path']?.toString(),
      shareId: json['share_id']?.toString(),
    );
  }

  String getStreamUrl(String defaultHost) {
    final host = sourceNodeHost.isNotEmpty ? sourceNodeHost : defaultHost;
    final cleanHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    return "$cleanHost/api/stream/$id";
  }

  String getCoverUrl(String defaultHost) {
    final host = sourceNodeHost.isNotEmpty ? sourceNodeHost : defaultHost;
    final cleanHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    return "$cleanHost/api/cover/$id";
  }

  String get formattedDuration {
    final totalSeconds = duration.toInt();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }
}
