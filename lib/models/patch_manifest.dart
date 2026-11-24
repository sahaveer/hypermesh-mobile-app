class PatchManifest {
  final String patchId;
  final String name;
  final String version;
  final String author;
  final String description;
  final String endpoint;
  final List<String> supportedFormats;
  final DateTime appliedAt;

  PatchManifest({
    required this.patchId,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.endpoint,
    required this.supportedFormats,
    required this.appliedAt,
  });

  factory PatchManifest.fromJson(Map<String, dynamic> json) {
    return PatchManifest(
      patchId: json['patch_id'] as String? ?? 'ytdlp_server_importer',
      name: json['name'] as String? ?? 'Web & YouTube Importer',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Community / Personal',
      description: json['description'] as String? ?? 'Server-side yt-dlp downloader extension.',
      endpoint: json['endpoint'] as String? ?? '/api/download',
      supportedFormats: (json['supported_formats'] as List?)?.map((e) => e.toString()).toList() ?? ['mp3', 'mp4'],
      appliedAt: json['applied_at'] != null ? DateTime.parse(json['applied_at']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'patch_id': patchId,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'endpoint': endpoint,
      'supported_formats': supportedFormats,
      'applied_at': appliedAt.toIso8601String(),
    };
  }
}
