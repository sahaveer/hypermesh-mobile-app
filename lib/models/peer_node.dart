class PeerNode {
  final String id;
  final String name;
  final String host;
  final int port;
  final int musicCount;
  final int videoCount;
  final bool isOnline;
  final DateTime lastSeen;
  final String appVersion;
  final int buildNumber;

  PeerNode({
    required this.id,
    required this.name,
    required this.host,
    this.port = 8000,
    this.musicCount = 0,
    this.videoCount = 0,
    this.isOnline = true,
    DateTime? lastSeen,
    this.appVersion = "1.0.0",
    this.buildNumber = 1,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get baseUrl {
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host;
    }
    return "http://$host:$port";
  }

  factory PeerNode.fromJson(Map<String, dynamic> json) {
    return PeerNode(
      id: json['id']?.toString() ?? json['device_id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['device_name']?.toString() ?? 'Peer Node',
      host: json['host']?.toString() ?? json['ip']?.toString() ?? '127.0.0.1',
      port: (json['port'] is num) ? (json['port'] as num).toInt() : 8000,
      musicCount: (json['music_count'] is num) ? (json['music_count'] as num).toInt() : 0,
      videoCount: (json['video_count'] is num) ? (json['video_count'] as num).toInt() : 0,
      isOnline: json['is_online'] ?? true,
      appVersion: json['app_version']?.toString() ?? '1.0.0',
      buildNumber: (json['build_number'] is num) ? (json['build_number'] as num).toInt() : 1,
    );
  }
}
