import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/video_item.dart';

class SharedMediaFile {
  final String id;
  final String path;
  final String name;
  final int size;
  final bool isVideo;
  final double duration; // In seconds
  final String resolution;

  SharedMediaFile({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.isVideo,
    this.duration = 0.0,
    this.resolution = "1080p FHD",
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'size': size,
    'isVideo': isVideo,
    'duration': duration,
    'resolution': resolution,
  };

  factory SharedMediaFile.fromJson(Map<String, dynamic> json) => SharedMediaFile(
    id: json['id'] ?? '',
    path: json['path'] ?? '',
    name: json['name'] ?? '',
    size: json['size'] ?? 0,
    isVideo: json['isVideo'] ?? false,
    duration: (json['duration'] is num) ? (json['duration'] as num).toDouble() : 0.0,
    resolution: json['resolution'] ?? "1080p FHD",
  );
}

class LocalMediaStore {
  static const String _storageKey = "hypermesh_shared_files_v1";
  final List<SharedMediaFile> _sharedFiles = [];

  List<SharedMediaFile> get sharedFiles => List.unmodifiable(_sharedFiles);
  List<SharedMediaFile> get sharedSongs => _sharedFiles.where((f) => !f.isVideo).toList();
  List<SharedMediaFile> get sharedVideos => _sharedFiles.where((f) => f.isVideo).toList();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];
    _sharedFiles.clear();

    for (final raw in rawList) {
      try {
        final item = SharedMediaFile.fromJson(json.decode(raw));
        // Verify file still exists on disk
        if (File(item.path).existsSync()) {
          _sharedFiles.add(item);
        }
      } catch (_) {}
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = _sharedFiles.map((f) => json.encode(f.toJson())).toList();
    if (!await prefs.setStringList(_storageKey, rawList)) {
      throw FileSystemException('Could not save the local library');
    }
  }

  /// Lets the user pick audio or video files from device storage
  Future<List<SharedMediaFile>> pickAndAddFiles({bool isVideo = false}) async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: isVideo ? FileType.video : FileType.audio,
      );

      if (pickedFiles.isEmpty) {
        return [];
      }

      final added = <SharedMediaFile>[];
      for (final picked in pickedFiles) {
        if (picked.path == null) continue;
        final file = File(picked.path!);
        if (!file.existsSync()) continue;

        // Check if already shared
        if (_sharedFiles.any((f) => f.path == picked.path)) continue;

        final fileName = picked.name;
        final fileSize = file.existsSync() ? file.lengthSync() : (picked.lengthSync() ?? 0);
        final id = "local_${DateTime.now().microsecondsSinceEpoch}_${added.length}";

        // Estimate duration if unknown (approximate 1.5MB per min for 192k audio, 1GB per hr for video)
        double estimatedDuration = 0.0;
        if (isVideo) {
          final hours = fileSize / (1024 * 1024 * 1024); // ~1GB/hr
          estimatedDuration = (hours * 3600).clamp(60.0, 14400.0);
        } else {
          final mins = fileSize / (1.5 * 1024 * 1024);
          estimatedDuration = (mins * 60).clamp(30.0, 3600.0);
        }

        final item = SharedMediaFile(
          id: id,
          path: picked.path!,
          name: fileName,
          size: fileSize,
          isVideo: isVideo,
          duration: estimatedDuration,
          resolution: isVideo ? _guessResolution(fileName) : "",
        );

        _sharedFiles.insert(0, item);
        added.add(item);
      }

      if (added.isNotEmpty) {
        await save();
      }
      return added;
    } catch (e) {
      debugPrint("Error picking files: $e");
      return [];
    }
  }

  Future<void> removeFile(String id) async {
    _sharedFiles.removeWhere((f) => f.id == id);
    await save();
  }

  SharedMediaFile? getFileById(String id) {
    try {
      return _sharedFiles.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Converts shared files to Song objects for local mesh player
  List<Song> toSongs({required String nodeName, required String hostUrl, required String ownerId}) {
    return sharedSongs.map((f) {
      final title = cleanTitle(f.name);
      return Song(
        id: f.id,
        title: title,
        artist: "Local Device",
        album: "Device Storage",
        duration: f.duration > 0 ? f.duration : 180.0,
        ownerId: ownerId,
        ownerName: nodeName,
        sourceNodeName: nodeName,
        sourceNodeHost: hostUrl,
        isPeer: false,
        localFilePath: f.path,
      );
    }).toList();
  }

  /// Converts shared files to VideoItem objects for local mesh player
  List<VideoItem> toVideos({required String nodeName, required String hostUrl, required String ownerId}) {
    return sharedVideos.map((f) {
      final title = cleanTitle(f.name);
      return VideoItem(
        id: f.id,
        title: title,
        duration: f.duration > 0 ? f.duration : 3600.0,
        filesize: f.size,
        resolution: f.resolution,
        ownerId: ownerId,
        ownerName: nodeName,
        sourceNodeName: nodeName,
        sourceNodeHost: hostUrl,
        isPeer: false,
        localFilePath: f.path,
      );
    }).toList();
  }

  /// Pin/Save a peer's file directly to local device storage
  Future<String?> pinMediaLocally({
    required String downloadUrl,
    required String fileName,
    required bool isVideo,
    required Function(double progress)? onProgress,
    String? asset,
    required double duration,
    required String resolution,
  }) async {
    final client = http.Client();
    Directory? pinDirectory;
    SharedMediaFile? item;
    try {
      final documents = await getApplicationDocumentsDirectory();
      final directory = await Directory("${documents.path}/Hypermesh")
          .create(recursive: true);
      pinDirectory = await directory.createTemp('pinned_');
      final safeName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
      var name = safeName;
      late File target;
      int downloaded;
      if (asset != null) {
        target = File("${pinDirectory.path}/$name");
        final data = await rootBundle.load(asset);
        await target.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        downloaded = data.lengthInBytes;
        onProgress?.call(1);
      } else {
        final request = http.Request('GET', Uri.parse(downloadUrl));
        final response = await client.send(request).timeout(const Duration(seconds: 15));
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Download returned ${response.statusCode}');
        }
        final disposition = response.headers['content-disposition'] ?? '';
        final remoteName = RegExp(r'filename="?([^";]+)').firstMatch(disposition)?.group(1) ?? '';
        final extension = RegExp(r'\.(mp3|aac|m4a|flac|wav|ogg|opus|mp4|mkv|webm|mov|avi)$',
          caseSensitive: false).firstMatch(remoteName)?.group(0);
        if (extension != null) {
          final dot = safeName.lastIndexOf('.');
          name = (dot > 0 ? safeName.substring(0, dot) : safeName) + extension;
        }
        target = File("${pinDirectory.path}/$name");
        final contentLength = response.contentLength;
        downloaded = 0;
        final sink = target.openWrite();
        try {
          await sink.addStream(response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
            downloaded += chunk.length;
            if (contentLength != null && contentLength > 0) {
              onProgress?.call(downloaded / contentLength);
            }
            return chunk;
          }));
        } finally {
          await sink.close();
        }
        if (downloaded == 0 || (contentLength != null && contentLength != downloaded)) {
          throw const HttpException('Incomplete media download');
        }
      }

      item = SharedMediaFile(
        id: pinDirectory.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
        path: target.path,
        name: name,
        size: downloaded,
        isVideo: isVideo,
        duration: duration,
        resolution: resolution,
      );
      _sharedFiles.insert(0, item);
      await save();
      return target.path;
    } catch (e) {
      _sharedFiles.remove(item);
      if (pinDirectory != null) {
        try {
          await pinDirectory.delete(recursive: true);
        } on FileSystemException catch (error) {
          debugPrint('Error cleaning incomplete pin: $error');
        }
      }
      debugPrint('Error pinning media: $e');
      return null;
    } finally {
      client.close();
    }
  }

  static String cleanTitle(String rawName) {
    // Strip common movie/torrent suffixes (.mp4, 1080p, x264, etc.)
    var clean = rawName;
    clean = clean.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|mp3|m4a|flac|wav)$', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'[\._]'), ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean;
  }

  static String _guessResolution(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains("2160p") || lower.contains("4k")) return "4K UHD";
    if (lower.contains("1080p")) return "1080p FHD";
    if (lower.contains("720p")) return "720p HD";
    return "1080p FHD";
  }
}
