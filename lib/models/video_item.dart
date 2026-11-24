class VideoItem {
  final String id;
  final String title;
  final double duration;
  final int filesize;
  final String resolution;
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

  VideoItem({
    required this.id,
    required this.title,
    required this.duration,
    this.filesize = 0,
    this.resolution = "1080p",
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

  factory VideoItem.fromJson(
    Map<String, dynamic> json, {
    String sourceNodeName = "My Hub",
    String sourceNodeHost = "",
    bool isPeer = false,
    String? localFilePath,
  }) {
    return VideoItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Video',
      duration: (json['duration'] is num) ? (json['duration'] as num).toDouble() : 0.0,
      filesize: (json['filesize'] is num) ? (json['filesize'] as num).toInt() : 0,
      resolution: json['resolution']?.toString() ?? '1080p',
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

  String get formattedDuration {
    final totalSeconds = duration.toInt();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return "$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    }
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  String get formattedFilesize {
    if (filesize <= 0) return "";
    final mb = filesize / (1024 * 1024);
    if (mb >= 1000) {
      return "${(mb / 1024).toStringAsFixed(1)} GB";
    }
    return "${mb.toInt()} MB";
  }
}
