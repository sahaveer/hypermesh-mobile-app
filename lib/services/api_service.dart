import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/video_item.dart';
import '../models/peer_node.dart';

class ApiService {
  static const String defaultHost = "http://10.0.2.2:8000";
  String hostUrl;
  String? adminToken;
  final http.Client? httpClient;

  ApiService({String? initialHost, this.httpClient})
      : hostUrl = initialHost ?? defaultHost;

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) =>
      httpClient != null
          ? httpClient!.get(uri, headers: headers)
          : http.get(uri, headers: headers);

  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) =>
      httpClient != null
          ? httpClient!.post(uri, headers: headers, body: body)
          : http.post(uri, headers: headers, body: body);

  Future<http.Response> _delete(Uri uri, {Map<String, String>? headers}) =>
      httpClient != null
          ? httpClient!.delete(uri, headers: headers)
          : http.delete(uri, headers: headers);

  bool get isDemo => hostUrl == "http://demo.hub";

  bool get isAdmin => adminToken != null && adminToken!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_hub_host');
    if (saved != null && saved.trim().isNotEmpty) {
      hostUrl = saved.trim();
    }
    final savedToken = prefs.getString('server_admin_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      adminToken = savedToken;
    }
  }

  Future<void> setAdminToken(String? token) async {
    adminToken = token?.trim();
    final prefs = await SharedPreferences.getInstance();
    if (adminToken != null && adminToken!.isNotEmpty) {
      await prefs.setString('server_admin_token', adminToken!);
    } else {
      await prefs.remove('server_admin_token');
    }
  }

  Future<bool> verifyAdminPassword(String password) async {
    try {
      final clean = password.trim();
      final uri = Uri.parse("$hostUrl/api/settings");
      final response = await http.get(uri, headers: {
        'x-admin-token': clean,
      }).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        await setAdminToken(clean);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> deleteMediaOnServer(String mediaId) async {
    try {
      final uri = Uri.parse("$hostUrl/api/media/$mediaId");
      final headers = <String, String>{};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      final response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateHost(String newHost) async {
    var clean = newHost.trim();
    if (clean.contains("trycloudflare.com") ||
        clean.contains("cloudflare") ||
        clean.contains(".ts.net") ||
        clean.startsWith("https://")) {
      // Cloudflare tunnels & Tailscale Funnels always require HTTPS
      if (!clean.startsWith("https://")) {
        clean = "https://${clean.replaceAll('http://', '')}";
      }
    } else if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = "http://$clean";
    }

    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    hostUrl = clean;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_hub_host', hostUrl);
  }

  // --- SONGS ---
  Future<List<Song>> fetchLocalSongs() async {
    if (isDemo) return getDemoLocalSongs();
    try {
      final uri = Uri.parse("$hostUrl/api/songs?limit=1000");
      final response = await _get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['songs'] as List? ?? []);
        return list.map((item) => Song.fromJson(
          item,
          sourceNodeName: "My Hub",
          sourceNodeHost: hostUrl,
          isPeer: false,
        )).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<List<Song>> fetchPeerSongs(PeerNode peer) async {
    if (isDemo && peer.id.startsWith("demo-peer-")) return getDemoPeerSongs(peer);
    try {
      final uri = Uri.parse("${peer.baseUrl}/api/songs?scope=shared&limit=1000");
      final headers = <String, String>{};
      if (peer.meshToken != null && peer.meshToken!.isNotEmpty) {
        headers['x-mesh-token'] = peer.meshToken!;
      }
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['songs'] as List? ?? []);
        return list.map((item) => Song.fromJson(
          item,
          sourceNodeName: peer.name,
          sourceNodeHost: peer.baseUrl,
          isPeer: true,
          streamToken: peer.meshToken,
        )).toList();
      }
    } catch (_) {}

    return [];
  }

  // --- VIDEOS ---
  Future<List<VideoItem>> fetchLocalVideos() async {
    if (isDemo) return getDemoLocalVideos();
    try {
      final uri = Uri.parse("$hostUrl/api/videos?limit=500");
      final response = await _get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['videos'] as List? ?? []);
        return list.map((item) => VideoItem.fromJson(
          item,
          sourceNodeName: "My Hub",
          sourceNodeHost: hostUrl,
          isPeer: false,
        )).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<List<VideoItem>> fetchPeerVideos(PeerNode peer) async {
    if (isDemo && peer.id.startsWith("demo-peer-")) return getDemoPeerVideos(peer);
    try {
      final uri = Uri.parse("${peer.baseUrl}/api/videos?scope=shared&limit=500");
      final headers = <String, String>{};
      if (peer.meshToken != null && peer.meshToken!.isNotEmpty) {
        headers['x-mesh-token'] = peer.meshToken!;
      }
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['videos'] as List? ?? []);
        return list.map((item) => VideoItem.fromJson(
          item,
          sourceNodeName: peer.name,
          sourceNodeHost: peer.baseUrl,
          isPeer: true,
          streamToken: peer.meshToken,
        )).toList();
      }
    } catch (_) {}

    return [];
  }

  // --- PEERS ---
  Future<List<PeerNode>> fetchDiscoveredPeers() async {
    if (isDemo) return getDemoPeers();
    try {
      final uri = Uri.parse("$hostUrl/api/peers/connected");
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data['peers'] as List? ?? []);
        return list.map((item) => PeerNode.fromJson(item)).toList();
      }
    } catch (_) {}

    return [];
  }

  // --- ACTIONS ---
  Future<bool> toggleFavoriteOnServer(String mediaId) async {
    try {
      final uri = Uri.parse("$hostUrl/api/media/$mediaId/favorite");
      final response = await http.post(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> copyPeerMediaToServer(String shareId) async {
    try {
      final uri = Uri.parse("$hostUrl/api/peers/shares/${Uri.encodeComponent(shareId)}/copy-to-server");
      final response = await http.post(uri, headers: {
        if (isAdmin) 'x-admin-token': adminToken!,
      }).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Bundled media makes demo playback independent of the network.
  static const _demoAudio = 'assets/demo/mesh-audio.m4a';
  static const _demoVideo = 'assets/demo/mesh-video.mp4';

  List<Song> getDemoLocalSongs() => [_demoSong('demo-1', 'Mesh Signal')];

  List<VideoItem> getDemoLocalVideos() =>
      [_demoClip('vid-demo-1', 'Mesh Radar Preview')];

  List<PeerNode> getDemoPeers() => [
    PeerNode(
      id: 'demo-peer-1',
      name: 'Demo Peer',
      host: 'demo.hub',
      musicCount: 1,
      videoCount: 1,
      isOnline: true,
    ),
  ];

  List<Song> getDemoPeerSongs(PeerNode peer) =>
      [_demoSong('demo-peer-song-1', 'Signal Relay', peer)];

  List<VideoItem> getDemoPeerVideos(PeerNode peer) =>
      [_demoClip('vid-demo-peer-1', 'Peer Radar Preview', peer)];

  Song _demoSong(String id, String title, [PeerNode? peer]) => Song(
    id: id,
    title: title,
    artist: 'Hypermesh',
    album: 'Offline Demo',
    duration: 12,
    ownerId: peer?.id ?? 'demo-hub',
    ownerName: peer?.name ?? 'Demo Hub',
    sourceNodeName: peer?.name ?? 'Demo Hub',
    sourceNodeHost: 'http://demo.hub',
    isPeer: peer != null,
    demoAsset: _demoAudio,
  );

  VideoItem _demoClip(String id, String title, [PeerNode? peer]) => VideoItem(
    id: id,
    title: title,
    duration: 12,
    resolution: '360p',
    ownerId: peer?.id ?? 'demo-hub',
    ownerName: peer?.name ?? 'Demo Hub',
    sourceNodeName: peer?.name ?? 'Demo Hub',
    sourceNodeHost: 'http://demo.hub',
    isPeer: peer != null,
    demoAsset: _demoVideo,
  );

  // --- SERVER DOWNLOADER (YT-DLP EXTENSION BRIDGE) ---
  static String normalizeDownloadFormat(String format) {
    final clean = format.trim().toLowerCase();
    if (clean == 'mp3' || clean == 'audio') return 'audio';
    if (clean == 'mp4' || clean == 'video') return 'video';
    return clean;
  }

  static String normalizeDownloadQuality(String format, String quality) {
    if (normalizeDownloadFormat(format) == 'audio') return 'best';
    final clean = quality.trim().toLowerCase();
    if (clean == '4k' || clean == '2160' || clean == '2160p') return '4k';
    if (clean == '1080' || clean == '1080p') return '1080p';
    if (clean == '720' || clean == '720p') return '720p';
    return 'best';
  }

  Future<bool> checkDownloaderAvailable() async {
    if (isDemo) return false;
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/status");
      final response = await _get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String? resolveDownloadFileUrl(Map<String, dynamic> task) {
    final rawUrl = (task['download_url'] as String?)?.trim();
    final taskId = (task['id'] as String?)?.trim();
    final pathOrUrl = (rawUrl != null && rawUrl.isNotEmpty)
        ? rawUrl
        : (taskId != null && taskId.isNotEmpty
            ? "/api/downloads/${Uri.encodeComponent(taskId)}/file"
            : null);
    if (pathOrUrl == null) return null;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    final cleanHost = hostUrl.endsWith('/') ? hostUrl.substring(0, hostUrl.length - 1) : hostUrl;
    final cleanPath = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return "$cleanHost$cleanPath";
  }

  Future<Map<String, dynamic>> startServerDownload({
    required String url,
    String format = "audio",
    String quality = "best",
    String destination = "server",
    String? clientId,
    String? deviceName,
    String? clipStart,
    String? clipEnd,
    bool subtitles = false,
    bool downloadPlaylist = false,
    String? proxy,
  }) async {
    if (isDemo) {
      return {'ok': false, 'error': 'Connect to your personal server first.'};
    }

    final normalizedFormat = normalizeDownloadFormat(format);
    final normalizedQuality = normalizeDownloadQuality(normalizedFormat, quality);
    final normalizedDest = destination == 'client' ? 'client' : 'server';

    try {
      final uri = Uri.parse("$hostUrl/api/download");
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      if (clientId != null && clientId.isNotEmpty) {
        headers['x-client-id'] = clientId;
      }

      final payload = <String, dynamic>{
        'url': url.trim(),
        'format': normalizedFormat,
        'quality': normalizedQuality,
        'destination': normalizedDest,
      };
      if (clientId != null && clientId.isNotEmpty) {
        payload['client_id'] = clientId;
      }
      if (deviceName != null && deviceName.isNotEmpty) {
        payload['device_name'] = deviceName;
      }
      if (clipStart != null && clipStart.trim().isNotEmpty) {
        payload['clip_start'] = clipStart.trim();
      }
      if (clipEnd != null && clipEnd.trim().isNotEmpty) {
        payload['clip_end'] = clipEnd.trim();
      }
      if (subtitles) {
        payload['subtitles'] = true;
      }
      if (downloadPlaylist) {
        payload['download_playlist'] = true;
      }
      if (proxy != null && proxy.trim().isNotEmpty) {
        payload['proxy'] = proxy.trim();
      }

      final response = await _post(
        uri,
        headers: headers,
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = Map<String, dynamic>.from(json.decode(response.body) as Map);
        decoded['ok'] = true;
        return decoded;
      }

      String errorMessage = 'Server returned HTTP ${response.statusCode}';
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          errorMessage = decoded['detail'].toString();
        }
      } catch (_) {}
      return {'ok': false, 'error': errorMessage};
    } catch (_) {
      return {'ok': false, 'error': 'Could not reach server ($hostUrl).'};
    }
  }

  Future<List<Map<String, dynamic>>> fetchDownloadStatus() async {
    if (isDemo) return [];
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/status");
      final response = await _get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tasks = (data['tasks'] as List? ?? []);
        return tasks.map((t) => Map<String, dynamic>.from(t as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> clearDownloadHistory() async {
    if (isDemo) return false;
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/clear");
      final headers = <String, String>{};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      final response = await _post(uri, headers: headers).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pauseDownload(String taskId) async {
    if (isDemo) return false;
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/${Uri.encodeComponent(taskId)}/pause");
      final headers = <String, String>{};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      final response = await _post(uri, headers: headers).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resumeDownload(String taskId) async {
    if (isDemo) return false;
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/${Uri.encodeComponent(taskId)}/resume");
      final headers = <String, String>{};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      final response = await _post(uri, headers: headers).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteDownload(String taskId) async {
    if (isDemo) return false;
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/${Uri.encodeComponent(taskId)}");
      final headers = <String, String>{};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      final response = await _delete(uri, headers: headers).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> editDownload(String taskId, {String? url, String? proxy}) async {
    if (isDemo) return false;
    try {
      final uri = Uri.parse("$hostUrl/api/downloads/${Uri.encodeComponent(taskId)}");
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (adminToken != null && adminToken!.isNotEmpty) {
        headers['x-admin-token'] = adminToken!;
      }
      final body = <String, dynamic>{};
      if (url != null) body['url'] = url.trim();
      if (proxy != null) body['proxy'] = proxy.trim();
      final response = await (httpClient != null
              ? httpClient!.patch(uri, headers: headers, body: json.encode(body))
              : http.patch(uri, headers: headers, body: json.encode(body)))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> searchDownloader({
    required String query,
    int limit = 8,
    bool includeYoutube = false,
    String? clientId,
  }) async {
    if (isDemo) {
      return {'ok': false, 'error': 'Connect to your personal server first.'};
    }

    try {
      final params = <String, String>{
        'q': query.trim(),
        'limit': limit.toString(),
        'include_youtube': includeYoutube ? 'true' : 'false',
      };
      if (clientId != null && clientId.isNotEmpty) {
        params['client_id'] = clientId;
      }
      final uri = Uri.parse("$hostUrl/api/downloader/search").replace(queryParameters: params);
      final response = await _get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final decoded = Map<String, dynamic>.from(json.decode(response.body) as Map);
        decoded['ok'] = true;
        return decoded;
      }
      String errorMessage = 'Server returned HTTP ${response.statusCode}';
      try {
        final decoded = json.decode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          errorMessage = decoded['detail'].toString();
        }
      } catch (_) {}
      return {'ok': false, 'error': errorMessage};
    } catch (_) {
      return {'ok': false, 'error': 'Could not search on server ($hostUrl).'};
    }
  }

  Future<Map<String, dynamic>?> fetchSongById(String songId) async {
    if (isDemo) return null;
    try {
      final uri = Uri.parse("$hostUrl/api/song/${Uri.encodeComponent(songId)}");
      final response = await _get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body) as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Computes a streaming SHA-256 hex digest without buffering the entire file in RAM.
  static Future<String> computeFileSha256(File file) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.value.toString();
  }

  /// Fetches photos stored on the connected Hub.
  Future<List<Map<String, dynamic>>> fetchHubPhotos({int limit = 200}) async {
    if (isDemo) return [];
    try {
      final uri = Uri.parse("$hostUrl/api/photos?limit=$limit");
      final response = await _get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final list = decoded['photos'] as List? ?? [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  String getPhotoThumbUrl(String photoId) =>
      "$hostUrl/api/photo/${Uri.encodeComponent(photoId)}/thumb";

  String getPhotoRawUrl(String photoId) =>
      "$hostUrl/api/photo/${Uri.encodeComponent(photoId)}";

  /// Checks which photo SHA-256 hashes already exist on the connected Hub.
  Future<Set<String>> checkExistingPhotoHashes(List<String> hashes) async {
    if (isDemo || hashes.isEmpty) return {};
    try {
      final uri = Uri.parse("$hostUrl/api/upload/photos/check");
      final response = await _post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'hashes': hashes}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final existing = (decoded['existing'] as List? ?? []);
        return existing.map((e) => e.toString().toLowerCase()).toSet();
      }
    } catch (_) {}
    return {};
  }

  /// Uploads any file (including 1 GB+ media) in resumable chunks with SHA-256 verification.
  Future<Map<String, dynamic>> uploadFileChunked({
    required File file,
    String? contentHash,
    String? mediaType,
    String? clientId,
    String? deviceName,
    int chunkSize = 4 * 1024 * 1024,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (isDemo) {
      return {'ok': false, 'error': 'Connect to a personal Hypermesh Hub first.'};
    }

    final totalSize = await file.length();
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final resolvedHash = contentHash ?? await computeFileSha256(file);

    try {
      final initUri = Uri.parse("$hostUrl/api/upload/chunked/init");
      final initHeaders = <String, String>{'Content-Type': 'application/json'};
      if (adminToken != null && adminToken!.isNotEmpty) {
        initHeaders['x-admin-token'] = adminToken!;
      }

      final initResp = await _post(
        initUri,
        headers: initHeaders,
        body: json.encode({
          'filename': fileName,
          'total_size': totalSize,
          'chunk_size': chunkSize,
          'content_hash': resolvedHash,
          'media_type': ?mediaType,
          'client_id': ?clientId,
          'device_name': ?deviceName,
        }),
      ).timeout(const Duration(seconds: 20));

      if (initResp.statusCode != 200) {
        return {'ok': false, 'error': 'Init failed (HTTP ${initResp.statusCode})'};
      }

      final initData = json.decode(initResp.body) as Map<String, dynamic>;
      if (initData['deduplicated'] == true || initData['status'] == 'duplicate') {
        onProgress?.call(totalSize, totalSize);
        return {'ok': true, 'status': 'duplicate', 'deduplicated': true, 'filename': fileName};
      }

      final uploadId = initData['upload_id']?.toString() ?? '';
      if (uploadId.isEmpty) {
        return {'ok': false, 'error': 'Server did not return an upload_id'};
      }

      final serverChunkSize = (initData['chunk_size'] is num)
          ? (initData['chunk_size'] as num).toInt()
          : chunkSize;
      int offset = (initData['next_offset'] is num)
          ? (initData['next_offset'] as num).toInt()
          : 0;

      onProgress?.call(offset, totalSize);

      final raf = await file.open(mode: FileMode.read);
      try {
        while (offset < totalSize) {
          final remaining = totalSize - offset;
          final readLen = remaining < serverChunkSize ? remaining : serverChunkSize;
          await raf.setPosition(offset);
          final bytes = await raf.read(readLen);

          bool chunkSent = false;
          for (int attempt = 0; attempt < 3; attempt++) {
            try {
              final putUri = Uri.parse(
                "$hostUrl/api/upload/chunked/${Uri.encodeComponent(uploadId)}?offset=$offset",
              );
              final putHeaders = <String, String>{
                'Content-Type': 'application/octet-stream',
              };
              if (adminToken != null && adminToken!.isNotEmpty) {
                putHeaders['x-admin-token'] = adminToken!;
              }
              final putResp = await (httpClient != null
                      ? httpClient!.put(putUri, headers: putHeaders, body: bytes)
                      : http.put(putUri, headers: putHeaders, body: bytes))
                  .timeout(const Duration(seconds: 60));

              if (putResp.statusCode == 200) {
                final putData = json.decode(putResp.body) as Map<String, dynamic>;
                offset = (putData['next_offset'] is num)
                    ? (putData['next_offset'] as num).toInt()
                    : (offset + bytes.length);
                chunkSent = true;
                break;
              } else if (putResp.statusCode == 409) {
                final expected = int.tryParse(putResp.headers['x-expected-offset'] ?? '');
                if (expected != null) {
                  offset = expected;
                  chunkSent = true;
                  break;
                }
              }
            } catch (_) {
              if (attempt == 2) rethrow;
              await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
            }
          }

          if (!chunkSent) {
            return {'ok': false, 'error': 'Chunk upload failed at offset $offset'};
          }
          onProgress?.call(offset, totalSize);
        }
      } finally {
        await raf.close();
      }

      final completeUri = Uri.parse(
        "$hostUrl/api/upload/chunked/${Uri.encodeComponent(uploadId)}/complete",
      );
      final completeHeaders = <String, String>{};
      if (adminToken != null && adminToken!.isNotEmpty) {
        completeHeaders['x-admin-token'] = adminToken!;
      }
      final completeResp = await _post(
        completeUri,
        headers: completeHeaders,
      ).timeout(const Duration(seconds: 45));

      if (completeResp.statusCode == 200) {
        final done = Map<String, dynamic>.from(json.decode(completeResp.body) as Map);
        done['ok'] = true;
        return done;
      }
      return {'ok': false, 'error': 'Finalize failed (HTTP ${completeResp.statusCode})'};
    } catch (e) {
      return {'ok': false, 'error': 'Chunked upload error: $e'};
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
