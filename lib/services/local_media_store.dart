import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  static const String _foldersKey = "hypermesh_shared_folders_v1";

  static const Set<String> audioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wav',
    '.wma',
  };

  static const Set<String> videoExtensions = {
    '.mp4',
    '.mkv',
    '.mov',
    '.avi',
    '.m4v',
    '.webm',
    '.ts',
  };

  final List<SharedMediaFile> _sharedFiles = [];
  final List<String> _sharedFolders = [];

  List<SharedMediaFile> get sharedFiles => List.unmodifiable(_sharedFiles);
  List<SharedMediaFile> get sharedSongs => _sharedFiles.where((f) => !f.isVideo).toList();
  List<SharedMediaFile> get sharedVideos => _sharedFiles.where((f) => f.isVideo).toList();
  List<String> get sharedFolders => List.unmodifiable(_sharedFolders);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];
    final rawFolders = prefs.getStringList(_foldersKey) ?? [];
    _sharedFiles.clear();
    _sharedFolders.clear();

    for (final folder in rawFolders) {
      final clean = folder.trim();
      if (clean.isNotEmpty && !_sharedFolders.contains(clean) && Directory(clean).existsSync()) {
        _sharedFolders.add(clean);
      }
    }

    for (final raw in rawList) {
      try {
        final item = SharedMediaFile.fromJson(json.decode(raw));
        // Verify file still exists on disk
        if (File(item.path).existsSync()) {
          _sharedFiles.add(item);
        }
      } catch (_) {}
    }

    if (_sharedFolders.isNotEmpty) {
      await rescanAllFolders();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = _sharedFiles.map((f) => json.encode(f.toJson())).toList();
    if (!await prefs.setStringList(_storageKey, rawList)) {
      throw FileSystemException('Could not save the local library');
    }
    await prefs.setStringList(_foldersKey, _sharedFolders);
  }

  Future<bool> _ensureStoragePermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final statuses = await [
        Permission.audio,
        Permission.videos,
        Permission.storage,
      ].request();
      final audioOk = statuses[Permission.audio]?.isGranted ?? false;
      final videoOk = statuses[Permission.videos]?.isGranted ?? false;
      final storageOk = statuses[Permission.storage]?.isGranted ?? false;
      return audioOk || videoOk || storageOk;
    } catch (_) {
      return true;
    }
  }

  /// Opens native directory picker and scans all audio & video files inside.
  Future<({String? folderPath, List<SharedMediaFile> added, String? error})> pickAndAddFolder() async {
    try {
      final granted = await _ensureStoragePermissions();
      if (!granted) {
        return (
          folderPath: null,
          added: <SharedMediaFile>[],
          error: "Storage/media permission denied. Please allow Audio & Video access in Settings.",
        );
      }

      final folderPath = await FilePicker.getDirectoryPath(
        dialogTitle: "Select Music or Video Folder",
      );

      if (folderPath == null || folderPath.trim().isEmpty) {
        return (folderPath: null, added: <SharedMediaFile>[], error: null);
      }

      final added = await addAndScanFolder(folderPath);
      return (folderPath: folderPath, added: added, error: null);
    } catch (e) {
      debugPrint("Error picking folder: $e");
      return (folderPath: null, added: <SharedMediaFile>[], error: "Could not read folder: $e");
    }
  }

  /// Registers [folderPath] and scans all supported audio/video files inside it.
  Future<List<SharedMediaFile>> addAndScanFolder(String folderPath) async {
    final normalized = folderPath.trim();
    if (normalized.isEmpty) return [];

    if (!_sharedFolders.contains(normalized)) {
      _sharedFolders.add(normalized);
    }

    final added = await scanFolder(normalized);
    await save();
    return added;
  }

  /// Scans [folderPath] recursively for audio & video files not yet in [_sharedFiles].
  Future<List<SharedMediaFile>> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final existingPaths = _sharedFiles.map((f) => f.path).toSet();
    final added = <SharedMediaFile>[];
    final queue = <Directory>[dir];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false);
      } catch (_) {
        continue;
      }

      for (final entity in entries) {
        if (entity is Directory) {
          final base = _basename(entity.path);
          if (!base.startsWith('.')) {
            queue.add(entity);
          }
          continue;
        }
        if (entity is! File) continue;

        final filePath = entity.path;
        if (existingPaths.contains(filePath)) continue;

        final ext = _extension(filePath);
        final isAudio = audioExtensions.contains(ext);
        final isVideo = videoExtensions.contains(ext);
        if (!isAudio && !isVideo) continue;

        int fileSize = 0;
        try {
          fileSize = entity.lengthSync();
        } catch (_) {}

        final fileName = _basename(filePath);
        final id = "local_${DateTime.now().microsecondsSinceEpoch}_${added.length}";
        final item = SharedMediaFile(
          id: id,
          path: filePath,
          name: fileName,
          size: fileSize,
          isVideo: isVideo,
          duration: _estimateDuration(fileSize, isVideo: isVideo),
          resolution: isVideo ? _guessResolution(fileName) : "",
        );

        _sharedFiles.insert(0, item);
        existingPaths.add(filePath);
        added.add(item);
      }
    }

    return added;
  }

  /// Prunes missing files and rescans every saved folder.
  Future<int> rescanAllFolders() async {
    _sharedFiles.removeWhere((item) => !File(item.path).existsSync());
    int totalAdded = 0;
    for (final folder in List<String>.from(_sharedFolders)) {
      final added = await scanFolder(folder);
      totalAdded += added.length;
    }
    await save();
    return totalAdded;
  }

  /// Removes a linked folder and unshares files located inside it.
  Future<void> removeFolder(String folderPath) async {
    final normalized = _normalizeDirPrefix(folderPath);
    _sharedFolders.removeWhere((f) => _normalizeDirPrefix(f) == normalized);
    _sharedFiles.removeWhere((item) {
      final itemNorm = item.path.replaceAll('\\', '/');
      return itemNorm == normalized || itemNorm.startsWith('$normalized/');
    });
    await save();
  }

  int countFilesInFolder(String folderPath) {
    final normalized = _normalizeDirPrefix(folderPath);
    return _sharedFiles.where((item) {
      final itemNorm = item.path.replaceAll('\\', '/');
      return itemNorm == normalized || itemNorm.startsWith('$normalized/');
    }).length;
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
        final fileSize = file.lengthSync();
        final id = "local_${DateTime.now().microsecondsSinceEpoch}_${added.length}";

        final item = SharedMediaFile(
          id: id,
          path: picked.path!,
          name: fileName,
          size: fileSize,
          isVideo: isVideo,
          duration: _estimateDuration(fileSize, isVideo: isVideo),
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
                caseSensitive: false)
            .firstMatch(remoteName)
            ?.group(0);
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

  static double _estimateDuration(int fileSize, {required bool isVideo}) {
    if (isVideo) {
      final hours = fileSize / (1024 * 1024 * 1024);
      return (hours * 3600).clamp(60.0, 14400.0);
    }
    final mins = fileSize / (1.5 * 1024 * 1024);
    return (mins * 60).clamp(30.0, 3600.0);
  }

  static String _basename(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static String _extension(String path) {
    final base = _basename(path);
    final idx = base.lastIndexOf('.');
    return idx >= 0 ? base.substring(idx).toLowerCase() : '';
  }

  static String _normalizeDirPrefix(String path) {
    var norm = path.replaceAll('\\', '/');
    while (norm.endsWith('/') && norm.length > 1) {
      norm = norm.substring(0, norm.length - 1);
    }
    return norm;
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
