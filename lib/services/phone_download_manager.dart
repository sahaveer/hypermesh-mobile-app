import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PhoneDownloadTask {
  final String id;
  String url;
  String title;
  String fileName;
  String filePath;
  bool isVideo;
  bool isM3u8;
  String status; // 'pending', 'downloading', 'paused', 'completed', 'failed'
  double progress; // 0..100
  int downloadedBytes;
  int totalBytes;
  double speedBytesPerSec;
  int? etaSeconds;
  String? error;
  int createdAtMs;

  PhoneDownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.fileName,
    required this.filePath,
    required this.isVideo,
    this.isM3u8 = false,
    this.status = 'pending',
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.etaSeconds,
    this.error,
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'fileName': fileName,
        'filePath': filePath,
        'isVideo': isVideo,
        'isM3u8': isM3u8,
        'status': status,
        'progress': progress,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'speedBytesPerSec': speedBytesPerSec,
        'etaSeconds': etaSeconds,
        'error': error,
        'createdAtMs': createdAtMs,
      };

  factory PhoneDownloadTask.fromJson(Map<String, dynamic> json) => PhoneDownloadTask(
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Download',
        fileName: json['fileName']?.toString() ?? 'media.bin',
        filePath: json['filePath']?.toString() ?? '',
        isVideo: json['isVideo'] == true,
        isM3u8: json['isM3u8'] == true,
        status: json['status']?.toString() ?? 'paused',
        progress: (json['progress'] is num) ? (json['progress'] as num).toDouble() : 0.0,
        downloadedBytes: (json['downloadedBytes'] is num) ? (json['downloadedBytes'] as num).toInt() : 0,
        totalBytes: (json['totalBytes'] is num) ? (json['totalBytes'] as num).toInt() : 0,
        speedBytesPerSec: (json['speedBytesPerSec'] is num) ? (json['speedBytesPerSec'] as num).toDouble() : 0.0,
        etaSeconds: (json['etaSeconds'] is num) ? (json['etaSeconds'] as num).toInt() : null,
        error: json['error']?.toString(),
        createdAtMs: (json['createdAtMs'] is num) ? (json['createdAtMs'] as num).toInt() : null,
      );
}

typedef DownloadProgressNotify = Future<void> Function(
  String id,
  String title,
  int progress,
  String detail,
);
typedef DownloadCompleteNotify = Future<void> Function(
  String id,
  String title,
  bool success,
  String message,
);

/// Pure-Dart resumable & multi-chunk HTTP + M3U8 downloader for phone storage.
/// Persists task metadata and chunk offsets in JSON files so downloads survive
/// pause/resume and app restarts without requiring native SQLite plugins.
class PhoneDownloadManager extends ChangeNotifier {
  final http.Client Function() _clientFactory;
  final Future<Directory> Function()? baseDirProvider;
  final DownloadProgressNotify? onNotifyProgress;
  final DownloadCompleteNotify? onNotifyComplete;
  final Future<void> Function(PhoneDownloadTask task)? onFileCompleted;

  final List<PhoneDownloadTask> _tasks = [];
  final Map<String, Set<http.Client>> _activeClients = {};
  final Set<String> _interruptedIds = {};
  bool _initialized = false;
  Directory? _cachedDir;

  PhoneDownloadManager({
    http.Client Function()? clientFactory,
    this.baseDirProvider,
    this.onNotifyProgress,
    this.onNotifyComplete,
    this.onFileCompleted,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  List<PhoneDownloadTask> get tasks => List.unmodifiable(_tasks);

  static bool isDirectDownloadUrl(String raw) {
    final lower = raw.trim().toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) return false;
    final uri = Uri.tryParse(lower);
    if (uri == null) return false;
    final path = uri.path;
    return path.endsWith('.m3u8') ||
        RegExp(r'\.(mp3|m4a|aac|flac|wav|ogg|opus|mp4|mkv|webm|mov|avi|m4v|ts|zip|apk)$')
            .hasMatch(path);
  }

  Future<Directory> _ensureBaseDir() async {
    if (_cachedDir != null) return _cachedDir!;
    final root = baseDirProvider != null
        ? await baseDirProvider!()
        : Directory('${(await getApplicationDocumentsDirectory()).path}/Hypermesh/PhoneDownloads');
    await root.create(recursive: true);
    _cachedDir = root;
    return root;
  }

  Future<File> _queueFile() async {
    final dir = await _ensureBaseDir();
    return File('${dir.path}/phone_downloads.json');
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final qf = await _queueFile();
      if (await qf.exists()) {
        final decoded = json.decode(await qf.readAsString());
        if (decoded is List) {
          _tasks.clear();
          for (final item in decoded) {
            if (item is Map) {
              final task = PhoneDownloadTask.fromJson(Map<String, dynamic>.from(item));
              if (task.status == 'downloading' || task.status == 'pending') {
                task.status = 'paused';
                task.speedBytesPerSec = 0;
                task.etaSeconds = null;
              }
              _tasks.add(task);
            }
          }
          await _saveQueue();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('PhoneDownloadManager init error: $e');
    }
  }

  Future<void> _saveQueue() async {
    try {
      final qf = await _queueFile();
      await qf.writeAsString(json.encode(_tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('PhoneDownloadManager save error: $e');
    }
  }

  Future<PhoneDownloadTask> startDownload(
    String url, {
    String? title,
    bool? isVideo,
  }) async {
    await init();
    final dir = await _ensureBaseDir();
    final cleanUrl = url.trim();
    final uri = Uri.parse(cleanUrl);
    final rawName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'media';
    final isHls = cleanUrl.toLowerCase().contains('.m3u8');
    final guessedVideo = isVideo ??
        (isHls || RegExp(r'\.(mp4|mkv|webm|mov|avi|m4v|ts)$', caseSensitive: false).hasMatch(rawName));
    var safeName = (rawName.isEmpty ? 'download' : rawName)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (isHls) {
      safeName = '${safeName.replaceAll(RegExp(r'\.m3u8$', caseSensitive: false), '')}.ts';
    } else if (!safeName.contains('.')) {
      safeName = '$safeName.${guessedVideo ? 'mp4' : 'mp3'}';
    }

    final id = 'pdl_${DateTime.now().microsecondsSinceEpoch}';
    final targetPath = '${dir.path}/${id}_$safeName';
    final task = PhoneDownloadTask(
      id: id,
      url: cleanUrl,
      title: (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : safeName.replaceAll(RegExp(r'\.[^.]+$'), ''),
      fileName: safeName,
      filePath: targetPath,
      isVideo: guessedVideo,
      isM3u8: isHls,
      status: 'pending',
    );
    _tasks.insert(0, task);
    await _saveQueue();
    notifyListeners();

    unawaited(_runTask(task));
    return task;
  }

  Future<void> pause(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    _interruptedIds.add(id);
    final clients = _activeClients.remove(id);
    if (clients != null) {
      for (final c in clients) {
        c.close();
      }
    }
    final t = _tasks[idx];
    if (t.status == 'downloading' || t.status == 'pending') {
      t.status = 'paused';
      t.speedBytesPerSec = 0;
      t.etaSeconds = null;
      await _saveQueue();
      notifyListeners();
    }
  }

  Future<void> resume(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final t = _tasks[idx];
    if (t.status != 'paused' && t.status != 'failed') return;
    _interruptedIds.remove(id);
    t.status = 'pending';
    t.error = null;
    await _saveQueue();
    notifyListeners();
    unawaited(_runTask(t));
  }

  Future<void> editTask(String id, {String? url}) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final t = _tasks[idx];
    if (url != null && url.trim().isNotEmpty) {
      t.url = url.trim();
      await _saveQueue();
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    _interruptedIds.add(id);
    final clients = _activeClients.remove(id);
    if (clients != null) {
      for (final c in clients) {
        c.close();
      }
    }
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final t = _tasks.removeAt(idx);
    try {
      await File('${t.filePath}.part').delete();
    } catch (_) {}
    try {
      await File('${t.filePath}.part.meta.json').delete();
    } catch (_) {}
    await _saveQueue();
    notifyListeners();
  }

  Future<void> clearFinished() async {
    _tasks.removeWhere((t) => t.status == 'completed' || t.status == 'failed');
    await _saveQueue();
    notifyListeners();
  }

  Future<void> _runTask(PhoneDownloadTask task) async {
    try {
      if (task.isM3u8 || task.url.toLowerCase().contains('.m3u8')) {
        await _downloadM3u8(task);
      } else {
        await downloadResumableHttp(
          url: task.url,
          targetFile: File(task.filePath),
          clientFactory: _clientFactory,
          isInterrupted: () => _interruptedIds.contains(task.id),
          registerClient: (c) => _activeClients.putIfAbsent(task.id, () => {}).add(c),
          unregisterClient: (c) => _activeClients[task.id]?.remove(c),
          onProgress: (done, total, speed, eta) {
            task.status = 'downloading';
            task.downloadedBytes = done;
            task.totalBytes = total;
            task.progress = total > 0 ? (done / total) * 100.0 : 0.0;
            task.speedBytesPerSec = speed;
            task.etaSeconds = eta;
            notifyListeners();
            onNotifyProgress?.call(
              task.id,
              task.title,
              task.progress.round(),
              total > 0 ? '${(task.progress).toStringAsFixed(0)}%' : '${(done / (1024 * 1024)).toStringAsFixed(1)} MB',
            );
          },
        );
      }

      if (_interruptedIds.contains(task.id)) return;
      task.status = 'completed';
      task.progress = 100.0;
      task.speedBytesPerSec = 0;
      task.etaSeconds = 0;
      await _saveQueue();
      notifyListeners();
      await onFileCompleted?.call(task);
      await onNotifyComplete?.call(task.id, task.title, true, 'Saved to phone storage');
    } catch (e) {
      if (_interruptedIds.contains(task.id)) return;
      task.status = 'failed';
      task.speedBytesPerSec = 0;
      task.etaSeconds = null;
      task.error = e.toString();
      await _saveQueue();
      notifyListeners();
      await onNotifyComplete?.call(task.id, task.title, false, task.error ?? 'Download failed');
    } finally {
      _activeClients.remove(task.id);
    }
  }

  Future<void> _downloadM3u8(PhoneDownloadTask task) async {
    final client = _clientFactory();
    _activeClients.putIfAbsent(task.id, () => {}).add(client);
    try {
      var playlistUri = Uri.parse(task.url);
      var resp = await client.get(playlistUri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != HttpStatus.ok) {
        throw HttpException('Playlist returned HTTP ${resp.statusCode}');
      }
      var lines = const LineSplitter().convert(resp.body);

      // Handle master playlist -> pick highest bandwidth stream
      if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) {
        int bestBw = -1;
        String? bestRef;
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
            final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
            final bw = int.tryParse(bwMatch?.group(1) ?? '') ?? 0;
            for (int j = i + 1; j < lines.length; j++) {
              final next = lines[j].trim();
              if (next.isNotEmpty && !next.startsWith('#')) {
                if (bw > bestBw) {
                  bestBw = bw;
                  bestRef = next;
                }
                break;
              }
            }
          }
        }
        if (bestRef != null) {
          playlistUri = playlistUri.resolve(bestRef);
          resp = await client.get(playlistUri).timeout(const Duration(seconds: 15));
          lines = const LineSplitter().convert(resp.body);
        }
      }

      final segments = <Uri>[];
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        segments.add(playlistUri.resolve(line));
      }
      if (segments.isEmpty) {
        throw const HttpException('No media segments found in M3U8 playlist');
      }

      final partFile = File('${task.filePath}.part');
      final metaFile = File('${task.filePath}.part.meta.json');
      int nextIndex = 0;
      if (await metaFile.exists() && await partFile.exists()) {
        try {
          final saved = json.decode(await metaFile.readAsString());
          if (saved['url'] == task.url && saved['total'] == segments.length) {
            nextIndex = (saved['nextIndex'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }

      final sink = partFile.openWrite(mode: nextIndex > 0 ? FileMode.append : FileMode.write);
      int bytesDone = await partFile.exists() ? await partFile.length() : 0;
      final sw = Stopwatch()..start();
      try {
        for (int i = nextIndex; i < segments.length; i++) {
          if (_interruptedIds.contains(task.id)) break;
          final segResp = await client.get(segments[i]).timeout(const Duration(seconds: 20));
          if (segResp.statusCode != HttpStatus.ok) {
            throw HttpException('Segment $i failed (HTTP ${segResp.statusCode})');
          }
          sink.add(segResp.bodyBytes);
          bytesDone += segResp.bodyBytes.length;
          await metaFile.writeAsString(json.encode({
            'url': task.url,
            'total': segments.length,
            'nextIndex': i + 1,
          }));
          final elapsedSec = max(0.1, sw.elapsedMilliseconds / 1000.0);
          task.status = 'downloading';
          task.downloadedBytes = bytesDone;
          task.progress = ((i + 1) / segments.length) * 100.0;
          task.speedBytesPerSec = bytesDone / elapsedSec;
          notifyListeners();
          onNotifyProgress?.call(
            task.id,
            task.title,
            task.progress.round(),
            'Segment ${i + 1}/${segments.length}',
          );
        }
      } finally {
        await sink.close();
      }

      if (_interruptedIds.contains(task.id)) return;
      await partFile.rename(task.filePath);
      if (await metaFile.exists()) await metaFile.delete();
      task.totalBytes = bytesDone;
    } finally {
      _activeClients[task.id]?.remove(client);
      client.close();
    }
  }

  /// Resumable, multi-chunk HTTP Range downloader writing directly at byte offsets
  /// into `<target>.part` (no merge step). Reused by both PhoneDownloadManager and
  /// LocalMediaStore.pinMediaLocally().
  static Future<File> downloadResumableHttp({
    required String url,
    required File targetFile,
    http.Client Function()? clientFactory,
    bool Function()? isInterrupted,
    void Function(http.Client client)? registerClient,
    void Function(http.Client client)? unregisterClient,
    void Function(int downloaded, int total, double speedBytesPerSec, int? etaSeconds)? onProgress,
    int maxChunks = 4,
  }) async {
    final makeClient = clientFactory ?? http.Client.new;
    final probeClient = makeClient();
    registerClient?.call(probeClient);

    int totalBytes = 0;
    bool acceptRanges = false;
    try {
      final headResp = await probeClient.head(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (headResp.statusCode >= 200 && headResp.statusCode < 400) {
        totalBytes = int.tryParse(headResp.headers['content-length'] ?? '') ?? 0;
        acceptRanges = (headResp.headers['accept-ranges'] ?? '').toLowerCase().contains('bytes');
      }
    } catch (_) {
      // Fallback to GET below
    } finally {
      unregisterClient?.call(probeClient);
      probeClient.close();
    }

    final partFile = File('${targetFile.path}.part');
    final metaFile = File('${targetFile.path}.part.meta.json');

    if (!acceptRanges || totalBytes < 1024 * 1024) {
      // Single-stream resumable download
      int existing = await partFile.exists() ? await partFile.length() : 0;
      final client = makeClient();
      registerClient?.call(client);
      try {
        final req = http.Request('GET', Uri.parse(url));
        if (acceptRanges && existing > 0) {
          req.headers['Range'] = 'bytes=$existing-';
        } else {
          existing = 0;
        }
        final resp = await client.send(req).timeout(const Duration(seconds: 20));
        if (resp.statusCode != HttpStatus.ok && resp.statusCode != HttpStatus.partialContent) {
          throw HttpException('Download returned ${resp.statusCode}');
        }
        if (resp.statusCode == HttpStatus.ok) {
          existing = 0;
          totalBytes = resp.contentLength ?? totalBytes;
        } else if (totalBytes <= 0 && resp.contentLength != null) {
          totalBytes = existing + resp.contentLength!;
        }

        final sink = partFile.openWrite(mode: existing > 0 ? FileMode.append : FileMode.write);
        int downloaded = existing;
        final sw = Stopwatch()..start();
        try {
          await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
            if (isInterrupted?.call() == true) break;
            sink.add(chunk);
            downloaded += chunk.length;
            final sec = max(0.1, sw.elapsedMilliseconds / 1000.0);
            final speed = (downloaded - existing) / sec;
            final eta = (totalBytes > 0 && speed > 0)
                ? ((totalBytes - downloaded) / speed).round()
                : null;
            onProgress?.call(downloaded, totalBytes, speed, eta);
          }
        } finally {
          await sink.close();
        }
        if (isInterrupted?.call() == true) {
          throw const HttpException('Download paused');
        }
        if (downloaded == 0 || (totalBytes > 0 && downloaded != totalBytes)) {
          throw const HttpException('Incomplete media download');
        }
        if (await targetFile.exists()) await targetFile.delete();
        await partFile.rename(targetFile.path);
        return targetFile;
      } finally {
        unregisterClient?.call(client);
        client.close();
      }
    }

    // Multi-chunk Range download writing directly to pre-allocated .part file
    List<List<int>> ranges = [];
    if (await metaFile.exists() && await partFile.exists() && await partFile.length() == totalBytes) {
      try {
        final saved = json.decode(await metaFile.readAsString());
        if (saved['url'] == url && saved['totalBytes'] == totalBytes && saved['ranges'] is List) {
          ranges = (saved['ranges'] as List)
              .map<List<int>>((r) => (r as List).map((n) => (n as num).toInt()).toList())
              .toList();
        }
      } catch (_) {
        ranges = [];
      }
    }

    if (ranges.isEmpty) {
      final chunkCount = min(maxChunks, max(2, totalBytes ~/ (512 * 1024)));
      final slice = totalBytes ~/ chunkCount;
      for (int i = 0; i < chunkCount; i++) {
        final s = i * slice;
        final e = (i == chunkCount - 1) ? totalBytes - 1 : ((i + 1) * slice - 1);
        ranges.add([s, e, s]); // [start, end, offset]
      }
      final raf = await partFile.open(mode: FileMode.write);
      await raf.truncate(totalBytes);
      await raf.close();
      await metaFile.writeAsString(json.encode({
        'url': url,
        'totalBytes': totalBytes,
        'ranges': ranges,
      }));
    }

    final raf = await partFile.open(mode: FileMode.append);
    final initialDone = ranges.fold<int>(0, (sum, r) => sum + max(0, r[2] - r[0]));
    final sw = Stopwatch()..start();
    var writeChain = Future<void>.value();

    Future<void> writeOffset(int offset, List<int> bytes) {
      writeChain = writeChain.then((_) async {
        await raf.setPosition(offset);
        await raf.writeFrom(bytes);
      });
      return writeChain;
    }

    Future<void> downloadSlice(List<int> r) async {
      if (r[2] > r[1]) return;
      final client = makeClient();
      registerClient?.call(client);
      try {
        final req = http.Request('GET', Uri.parse(url));
        req.headers['Range'] = 'bytes=${r[2]}-${r[1]}';
        final resp = await client.send(req).timeout(const Duration(seconds: 20));
        if (resp.statusCode != HttpStatus.partialContent && resp.statusCode != HttpStatus.ok) {
          throw HttpException('Range chunk returned ${resp.statusCode}');
        }
        int sinceMeta = 0;
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
          if (isInterrupted?.call() == true) break;
          final pos = r[2];
          await writeOffset(pos, chunk);
          r[2] += chunk.length;
          sinceMeta += chunk.length;
          final totalDone = ranges.fold<int>(0, (sum, x) => sum + max(0, x[2] - x[0]));
          final sec = max(0.1, sw.elapsedMilliseconds / 1000.0);
          final speed = max(0.0, (totalDone - initialDone) / sec);
          final eta = speed > 0 ? ((totalBytes - totalDone) / speed).round() : null;
          onProgress?.call(totalDone, totalBytes, speed, eta);
          if (sinceMeta >= 256 * 1024) {
            sinceMeta = 0;
            await metaFile.writeAsString(json.encode({
              'url': url,
              'totalBytes': totalBytes,
              'ranges': ranges,
            }));
          }
        }
      } finally {
        unregisterClient?.call(client);
        client.close();
      }
    }

    try {
      await Future.wait(ranges.map(downloadSlice));
      await writeChain;
      await metaFile.writeAsString(json.encode({
        'url': url,
        'totalBytes': totalBytes,
        'ranges': ranges,
      }));
    } finally {
      await raf.close();
    }

    if (isInterrupted?.call() == true) {
      throw const HttpException('Download paused');
    }
    final totalWritten = ranges.fold<int>(0, (sum, r) => sum + max(0, r[2] - r[0]));
    if (totalWritten != totalBytes) {
      throw const HttpException('Incomplete chunked download');
    }
    if (await targetFile.exists()) await targetFile.delete();
    await partFile.rename(targetFile.path);
    if (await metaFile.exists()) await metaFile.delete();
    return targetFile;
  }
}
