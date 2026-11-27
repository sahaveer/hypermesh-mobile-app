import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'background_mesh_service.dart';

String _basenameOf(String path) => path.split(RegExp(r'[/\\]')).last;

String _extOf(String path) {
  final name = _basenameOf(path);
  final dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot).toLowerCase() : '';
}

class GallerySyncResult {
  final int scanned;
  final int uploaded;
  final int deduplicated;
  final int pending;
  final int failed;
  final String message;

  const GallerySyncResult({
    this.scanned = 0,
    this.uploaded = 0,
    this.deduplicated = 0,
    this.pending = 0,
    this.failed = 0,
    this.message = '',
  });
}

class GallerySyncService {
  static const String _keyEnabled = 'gallery_sync_enabled_v1';
  static const String _keyWifiOnly = 'gallery_sync_wifi_only_v1';
  static const String _keySyncedCount = 'gallery_sync_synced_count_v1';
  static const String _keySyncedHashes = 'gallery_sync_known_hashes_v1';

  static const Set<String> photoExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
  };

  bool _enabled = false;
  bool _wifiOnly = true;
  bool _isSyncing = false;
  int _syncedCount = 0;
  double _progress = 0.0;
  String _statusText = 'Idle';
  final Set<String> _knownSyncedHashes = {};

  bool get isEnabled => _enabled;
  bool get wifiOnly => _wifiOnly;
  bool get isSyncing => _isSyncing;
  int get syncedCount => _syncedCount;
  double get progress => _progress;
  String get statusText => _statusText;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    _wifiOnly = prefs.getBool(_keyWifiOnly) ?? true;
    _syncedCount = prefs.getInt(_keySyncedCount) ?? 0;
    final savedHashes = prefs.getStringList(_keySyncedHashes) ?? const [];
    _knownSyncedHashes
      ..clear()
      ..addAll(savedHashes);
    if (_enabled) {
      _statusText = _syncedCount > 0 ? 'Enabled ($_syncedCount backed up)' : 'Enabled • Waiting for sync';
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    _statusText = value ? 'Enabled • Ready to sync' : 'Disabled';
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWifiOnly, value);
  }

  Future<bool> ensurePhotoPermissions() async {
    if (!Platform.isAndroid) return true;
    try {
      final statuses = await [
        Permission.photos,
        Permission.storage,
      ].request();
      final photosOk = statuses[Permission.photos]?.isGranted ?? false;
      final storageOk = statuses[Permission.storage]?.isGranted ?? false;
      return photosOk || storageOk;
    } catch (_) {
      return true;
    }
  }

  List<Directory> _candidateGalleryDirs() {
    if (Platform.isAndroid) {
      const roots = [
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Download',
      ];
      return roots.map((path) => Directory(path)).where((d) => d.existsSync()).toList();
    }
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];
    final pics = Directory('$home${Platform.pathSeparator}Pictures');
    return pics.existsSync() ? [pics] : const [];
  }

  Future<List<File>> scanLocalPhotos({int maxFiles = 200}) async {
    final dirs = _candidateGalleryDirs();
    final seenPaths = <String>{};
    final collected = <File>[];

    for (final dir in dirs) {
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final ext = _extOf(entity.path);
          if (!photoExtensions.contains(ext)) continue;
          final base = _basenameOf(entity.path);
          if (base.startsWith('.')) continue;
          if (!seenPaths.add(entity.path)) continue;
          final stat = await entity.stat();
          if (stat.size < 1024) continue;
          collected.add(entity);
          if (collected.length >= maxFiles) break;
        }
      } catch (_) {}
      if (collected.length >= maxFiles) break;
    }
    return collected;
  }

  Future<GallerySyncResult> syncNow({
    required ApiService apiService,
    required String clientId,
    required String deviceName,
    void Function()? onUpdate,
  }) async {
    if (_isSyncing) {
      return const GallerySyncResult(message: 'Sync already in progress');
    }
    if (apiService.isDemo) {
      _statusText = 'Connect to a Hub first';
      onUpdate?.call();
      return GallerySyncResult(message: _statusText);
    }
    if (_wifiOnly && Platform.isAndroid) {
      final wifi = await BackgroundMeshService.isWifiConnected();
      if (!wifi) {
        _statusText = 'Paused (waiting for Wi-Fi)';
        onUpdate?.call();
        return GallerySyncResult(message: _statusText);
      }
    }

    final permitted = await ensurePhotoPermissions();
    if (!permitted) {
      _statusText = 'Photo permission needed';
      onUpdate?.call();
      return GallerySyncResult(message: _statusText);
    }

    _isSyncing = true;
    _progress = 0.0;
    _statusText = 'Scanning gallery...';
    onUpdate?.call();

    int scanned = 0;
    int uploaded = 0;
    int deduplicated = 0;
    int pending = 0;
    int failed = 0;

    try {
      final files = await scanLocalPhotos();
      scanned = files.length;
      if (files.isEmpty) {
        _statusText = 'No photos found in DCIM / Pictures';
        return GallerySyncResult(scanned: 0, message: _statusText);
      }

      // Compute SHA-256 locally and skip already-known hashes first
      final candidates = <({File file, String hash})>[];
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final hash = await ApiService.computeFileSha256(file);
        if (_knownSyncedHashes.contains(hash)) {
          deduplicated++;
        } else {
          candidates.add((file: file, hash: hash));
        }
      }

      // Ask server in batches which hashes already exist on the Hub
      final missing = <({File file, String hash})>[];
      for (int i = 0; i < candidates.length; i += 50) {
        final slice = candidates.sublist(i, (i + 50).clamp(0, candidates.length));
        final serverExisting = await apiService.checkExistingPhotoHashes(
          slice.map((e) => e.hash).toList(),
        );
        for (final item in slice) {
          if (serverExisting.contains(item.hash)) {
            _knownSyncedHashes.add(item.hash);
            deduplicated++;
          } else {
            missing.add(item);
          }
        }
      }

      for (int i = 0; i < missing.length; i++) {
        final item = missing[i];
        _statusText = 'Backing up ${i + 1}/${missing.length}: ${_basenameOf(item.file.path)}';
        _progress = (i + 1) / missing.length;
        onUpdate?.call();

        final res = await apiService.uploadFileChunked(
          file: item.file,
          contentHash: item.hash,
          mediaType: 'photo',
          clientId: clientId,
          deviceName: deviceName,
        );
        if (res['ok'] == true) {
          _knownSyncedHashes.add(item.hash);
          if (res['status'] == 'duplicate') {
            deduplicated++;
          } else if (res['status'] == 'pending') {
            pending++;
            _syncedCount++;
          } else {
            uploaded++;
            _syncedCount++;
          }
        } else {
          failed++;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySyncedCount, _syncedCount);
      // Cap persisted hash cache to latest 2,000 entries to keep prefs compact
      final persisted = _knownSyncedHashes.toList();
      final trimmed = persisted.length > 2000
          ? persisted.sublist(persisted.length - 2000)
          : persisted;
      await prefs.setStringList(_keySyncedHashes, trimmed);

      _progress = 1.0;
      _statusText = missing.isEmpty
          ? 'All $scanned photos up to date'
          : 'Synced $uploaded new • $deduplicated skipped${pending > 0 ? ' • $pending pending' : ''}';
      return GallerySyncResult(
        scanned: scanned,
        uploaded: uploaded,
        deduplicated: deduplicated,
        pending: pending,
        failed: failed,
        message: _statusText,
      );
    } finally {
      _isSyncing = false;
      onUpdate?.call();
    }
  }
}
