class Playlist {
  final String id;
  final String name;
  final List<String> songIds;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    List<String>? songIds,
    DateTime? createdAt,
  })  : songIds = songIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'song_ids': songIds,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Playlist',
      songIds: (json['song_ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
