import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'local_media_store.dart';
import '../config/app_config.dart';
import 'background_mesh_service.dart';

class LocalMeshServer {
  final LocalMediaStore mediaStore;
  final String deviceId;
  String deviceName;

  HttpServer? _server;
  int _port = 8080;
  String _localIp = "127.0.0.1";
  bool _isRunning = false;

  LocalMeshServer({
    required this.mediaStore,
    required this.deviceId,
    required this.deviceName,
  });

  bool get isRunning => _isRunning;
  int get port => _port;
  String get localIp => _localIp;
  String get serverUrl => "http://$_localIp:$_port";

  Future<bool> start() async {
    if (_isRunning) return true;

    // 1. Resolve Local IP (Wi-Fi or Hotspot interface)
    _localIp = await _resolveLocalIp();

    // 2. Bind HTTP Server (Try 8080, then 8081..8090, then 0)
    for (int p = 8080; p <= 8090; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p, shared: true);
        _port = p;
        _isRunning = true;
        break;
      } catch (_) {}
    }

    if (_server == null) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
        _port = _server!.port;
        _isRunning = true;
      } catch (e) {
        debugPrint("Failed to bind LocalMeshServer: $e");
        return false;
      }
    }

    debugPrint("⚡ LocalMeshServer running at http://$_localIp:$_port (Device: $deviceName)");

    // 3. Listen to incoming requests
    _server!.listen(
      _handleRequest,
      onError: (err) => debugPrint("LocalMeshServer error: $err"),
      cancelOnError: false,
    );

    return true;
  }

  Future<void> stop() async {
    _isRunning = false;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers to all responses
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Range, Content-Type, Accept');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (path == '/api/info' || path == '/api/peers/info') {
        await _handleInfo(request);
      } else if (path == '/api/songs') {
        await _handleSongs(request);
      } else if (path == '/api/videos') {
        await _handleVideos(request);
      } else if (path.startsWith('/api/stream/')) {
        final id = path.replaceFirst('/api/stream/', '').replaceFirst('song/', '').replaceFirst('video/', '');
        await _handleStream(request, id);
      } else if (path.startsWith('/api/download/')) {
        final id = path.replaceFirst('/api/download/', '');
        await _handleDownload(request, id);
      } else if (path == '/api/app/version') {
        await _handleAppVersion(request);
      } else if (path == '/api/app/latest.apk') {
        await _handleAppApkDownload(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(json.encode({'error': 'Endpoint not found'}));
        await request.response.close();
      }
    } catch (e) {
      debugPrint("Error handling request ($path): $e");
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleInfo(HttpRequest request) async {
    final info = {
      'id': deviceId,
      'device_id': deviceId,
      'name': deviceName,
      'device_name': deviceName,
      'host': _localIp,
      'port': _port,
      'url': serverUrl,
      'music_count': mediaStore.sharedSongs.length,
      'video_count': mediaStore.sharedVideos.length,
      'is_online': true,
      'app_version': AppConfig.appVersion,
      'build_number': AppConfig.buildNumber,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = HttpStatus.ok;
    request.response.write(json.encode(info));
    await request.response.close();
  }

  Future<void> _handleAppVersion(HttpRequest request) async {
    final versionInfo = {
      'version': AppConfig.appVersion,
      'build_number': AppConfig.buildNumber,
      'apk_url': "$serverUrl/api/app/latest.apk",
      'release_notes': "Shared via local peer ($deviceName)",
    };

    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = HttpStatus.ok;
    request.response.write(json.encode(versionInfo));
    await request.response.close();
  }

  Future<void> _handleAppApkDownload(HttpRequest request) async {
    final apkPath = await BackgroundMeshService.getAppSourceApkPath();
    if (apkPath == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(json.encode({'error': 'APK not available on this platform'}));
      await request.response.close();
      return;
    }

    final file = File(apkPath);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(json.encode({'error': 'Installed APK file not accessible'}));
      await request.response.close();
      return;
    }

    final fileSize = await file.length();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentLength = fileSize;
    request.response.headers.set('content-disposition', 'attachment; filename="hypermesh-v${AppConfig.appVersion}.apk"');
    request.response.headers.contentType = ContentType('application', 'vnd.android.package-archive');

    await file.openRead().pipe(request.response);
  }

  Future<void> _handleSongs(HttpRequest request) async {
    final songsList = mediaStore.sharedSongs.map((f) {
      return {
        'id': f.id,
        'title': LocalMediaStore.cleanTitle(f.name),
        'artist': deviceName,
        'album': 'Mesh Library',
        'duration': f.duration > 0 ? f.duration : 180.0,
        'owner_id': deviceId,
        'owner_name': deviceName,
        'stream_url': "$serverUrl/api/stream/${f.id}",
        'filesize': f.size,
        'is_peer': true,
      };
    }).toList();

    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = HttpStatus.ok;
    request.response.write(json.encode({'songs': songsList, 'count': songsList.length}));
    await request.response.close();
  }

  Future<void> _handleVideos(HttpRequest request) async {
    final videosList = mediaStore.sharedVideos.map((f) {
      return {
        'id': f.id,
        'title': LocalMediaStore.cleanTitle(f.name),
        'duration': f.duration > 0 ? f.duration : 3600.0,
        'filesize': f.size,
        'resolution': f.resolution,
        'owner_id': deviceId,
        'owner_name': deviceName,
        'stream_url': "$serverUrl/api/stream/${f.id}",
        'is_peer': true,
      };
    }).toList();

    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = HttpStatus.ok;
    request.response.write(json.encode({'videos': videosList, 'count': videosList.length}));
    await request.response.close();
  }

  /// High-performance HTTP 206 Byte-Range streaming for smooth seeking in videos and audio
  Future<void> _handleStream(HttpRequest request, String id) async {
    final item = mediaStore.getFileById(id);
    if (item == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(json.encode({'error': 'Media not found'}));
      await request.response.close();
      return;
    }

    final file = File(item.path);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fileSize = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final contentType = _getContentType(item.name, item.isVideo);

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      // Parse Range: bytes=start-end
      final parts = rangeHeader.substring(6).split('-');
      final startStr = parts[0].trim();
      final endStr = parts.length > 1 ? parts[1].trim() : '';

      int start = int.tryParse(startStr) ?? 0;
      int end = endStr.isNotEmpty ? (int.tryParse(endStr) ?? (fileSize - 1)) : (fileSize - 1);

      if (start >= fileSize) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileSize');
        await request.response.close();
        return;
      }

      end = min(end, fileSize - 1);
      final chunkLength = end - start + 1;

      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileSize');
      request.response.headers.contentLength = chunkLength;
      request.response.headers.contentType = contentType;

      // Pipe exact byte range to response
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        int remaining = chunkLength;
        const bufferSize = 64 * 1024; // 64 KB chunks

        while (remaining > 0) {
          final toRead = min(remaining, bufferSize);
          final chunk = await raf.read(toRead);
          if (chunk.isEmpty) break;
          request.response.add(chunk);
          remaining -= chunk.length;
        }
        await request.response.flush();
      } finally {
        await raf.close();
      }
      await request.response.close();
    } else {
      // Full file response
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentLength = fileSize;
      request.response.headers.contentType = contentType;

      await file.openRead().pipe(request.response);
    }
  }

  /// Download endpoint for 1-tap peer pinning
  Future<void> _handleDownload(HttpRequest request, String id) async {
    final item = mediaStore.getFileById(id);
    if (item == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = File(item.path);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fileSize = await file.length();
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentLength = fileSize;
    request.response.headers.set('content-disposition', 'attachment; filename="${item.name}"');
    request.response.headers.contentType = ContentType.binary;

    await file.openRead().pipe(request.response);
  }

  ContentType _getContentType(String fileName, bool isVideo) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp4')) return ContentType('video', 'mp4');
    if (lower.endsWith('.mkv')) return ContentType('video', 'x-matroska');
    if (lower.endsWith('.webm')) return ContentType('video', 'webm');
    if (lower.endsWith('.mov')) return ContentType('video', 'quicktime');
    if (lower.endsWith('.mp3')) return ContentType('audio', 'mpeg');
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return ContentType('audio', 'mp4');
    if (lower.endsWith('.flac')) return ContentType('audio', 'flac');
    if (lower.endsWith('.wav')) return ContentType('audio', 'wav');

    return isVideo ? ContentType('video', 'mp4') : ContentType('audio', 'mpeg');
  }

  static Future<String> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          // Prefer local LAN ranges (Wi-Fi / Hotspot)
          if (ip.startsWith("192.168.") || ip.startsWith("172.") || ip.startsWith("10.")) {
            return ip;
          }
        }
      }

      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (_) {}

    return "127.0.0.1";
  }
}
