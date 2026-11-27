import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/video_item.dart';
import 'phone_download_manager.dart';

class SharedMediaFile {
  final String id;
  final String path;
  final String name;
  final int size;
  final bool isVideo;
  final double duration; // In seconds
  final String resolution;
  /// Whether this file is exposed to mesh peers. Files added by the user
  /// explicitly (folder picker, file picker) default to true for backward
  /// compatibility; device-scan auto-discovered files default to false.
  bool sharedWithMesh;

  SharedMediaFile({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.isVideo,
    this.duration = 0.0,
    this.resolution = "1080p FHD",
    this.sharedWithMesh = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'size': size,
        'isVideo': isVideo,
        'duration': duration,
        'resolution': resolution,
        'sharedWithMesh': sharedWithMesh,
      };

  factory SharedMediaFile.fromJson(Map<String, dynamic> json) => SharedMediaFile(
        id: json['id'] ?? '',
        path: json['path'] ?? '',
        name: json['name'] ?? '',
        size: json['size'] ?? 0,
        isVideo: json['isVideo'] ?? false,
        duration: (json['duration'] is num) ? (json['duration'] as num).toDouble() : 0.0,
        resolution: json['resolution'] ?? "1080p FHD",
        // Default true keeps existing records sharing exactly as before upgrade.
        sharedWithMesh: json['sharedWithMesh'] is bool ? json['sharedWithMesh'] : true,
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
  // Every local audio/video the app knows about — visible to the user even
  // if it's not currently shared with the mesh.
  List<SharedMediaFile> get sharedSongs => _sharedFiles.where((f) => !f.isVideo).toList();
  List<SharedMediaFile> get sharedVideos => _sharedFiles.where((f) => f.isVideo).toList();
  // Only files the user has flagged as mesh-shared. This is what the local
  // HTTP server exposes to peers.
  List<SharedMediaFile> get meshSongs =>
      _sharedFiles.where((f) => !f.isVideo && f.sharedWithMesh).toList();
  List<SharedMediaFile> get meshVideos =>
      _sharedFiles.where((f) => f.isVideo && f.sharedWithMesh).toList();
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

  /// Toggles whether a locally-known file is served to mesh peers. The file
  /// stays in the library and remains playable on this device.
  Future<bool> setFileSharedWithMesh(String id, bool shared) async {
    final idx = _sharedFiles.indexWhere((f) => f.id == id);
    if (idx == -1) return false;
    _sharedFiles[idx].sharedWithMesh = shared;
    await save();
    return true;
  }

  /// Permanently deletes a local file from device storage AND the library
  /// index. Only touches files inside paths the app already tracks.
  /// Returns true if the physical file was removed (or was already gone).
  Future<bool> deleteLocalFile(String id) async {
    final idx = _sharedFiles.indexWhere((f) => f.id == id);
    if (idx == -1) return false;
    final item = _sharedFiles[idx];
    bool deleted = true;
    try {
      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint("Error deleting local file ${item.path}: $e");
      deleted = false;
    }
    _sharedFiles.removeAt(idx);
    await save();
    return deleted;
  }

  /// Well-known top-level public media locations on Android. The user can
  /// still add arbitrary folders with the picker; this just surfaces what
  /// most phones already have without requesting broad all-files storage access.
  static const List<String> _androidPublicMediaDirs = [
    '/storage/emulated/0/Music',
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/Podcasts',
    '/storage/emulated/0/Audiobooks',
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Ringtones',
    '/storage/emulated/0/Recordings',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video',
    '/storage/emulated/0/Telegram/Telegram Audio',
    '/storage/emulated/0/Telegram/Telegram Video',
  ];

  /// Scans the device's well-known public media directories (Music, Movies,
  /// Downloads, DCIM, …) and adds every audio/video file not already tracked.
  /// New entries default to [SharedMediaFile.sharedWithMesh] = false so the
  /// user's personal library isn't auto-exposed to peers.
  Future<({int added, bool permissionGranted, String? error})> scanDeviceMedia() async {
    try {
      final granted = await _ensureStoragePermissions();
      if (!granted) {
        return (added: 0, permissionGranted: false, error: "Media permission denied.");
      }
      if (!Platform.isAndroid) {
        return (added: 0, permissionGranted: true, error: "Device scan is Android-only right now.");
      }

      final existingPaths = _sharedFiles.map((f) => f.path).toSet();
      final addedItems = <SharedMediaFile>[];

      for (final dirPath in _androidPublicMediaDirs) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;
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
              if (!base.startsWith('.')) queue.add(entity);
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
            final id = "device_${DateTime.now().microsecondsSinceEpoch}_${addedItems.length}";
            final item = SharedMediaFile(
              id: id,
              path: filePath,
              name: fileName,
              size: fileSize,
              isVideo: isVideo,
              duration: _estimateDuration(fileSize, isVideo: isVideo),
              resolution: isVideo ? _guessResolution(fileName) : "",
              sharedWithMesh: false,
            );
            _sharedFiles.insert(0, item);
            existingPaths.add(filePath);
            addedItems.add(item);
          }
        }
      }

      if (addedItems.isNotEmpty) {
        await save();
      }
      return (added: addedItems.length, permissionGranted: true, error: null);
    } catch (e) {
      debugPrint("Error during device scan: $e");
      return (added: 0, permissionGranted: true, error: "Scan failed: $e");
    }
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

  /// Registers an already-downloaded file on disk into the local media library.
  Future<SharedMediaFile> registerDownloadedFile({
    required String id,
    required File file,
    required bool isVideo,
    double duration = 0.0,
    String resolution = '',
  }) async {
    final size = await file.length();
    final name = _basename(file.path);
    final item = SharedMediaFile(
      id: id,
      path: file.path,
      name: name,
      size: size,
      isVideo: isVideo,
      duration: duration > 0 ? duration : _estimateDuration(size, isVideo: isVideo),
      resolution: resolution.isNotEmpty ? resolution : (isVideo ? _guessResolution(name) : ''),
    );
    _sharedFiles.removeWhere((f) => f.path == file.path);
    _sharedFiles.insert(0, item);
    await save();
    return item;
  }

  /// Pin/Save a peer's file directly to local device storage using resumable chunked HTTP.
  Future<String?> pinMediaLocally({
    required String downloadUrl,
    required String fileName,
    required bool isVideo,
    required Function(double progress)? onProgress,
    String? asset,
    required double duration,
    required String resolution,
  }) async {
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
        target = File("${pinDirectory.path}/$name");
        await PhoneDownloadManager.downloadResumableHttp(
          url: downloadUrl,
          targetFile: target,
          onProgress: (done, total, _, _) {
            if (total > 0) {
              onProgress?.call(done / total);
            }
          },
        );
        downloaded = await target.length();
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
