import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/video_item.dart';
import '../models/peer_node.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';
import '../services/local_media_store.dart';
import '../services/local_mesh_server.dart';
import '../services/local_mesh_discovery.dart';
import '../services/background_mesh_service.dart';
import '../widgets/background_sharing_dialog.dart';
import '../services/app_update_service.dart';

enum MeshFilter { all, mine, peers, favorites }

class HypermeshProvider extends ChangeNotifier {
  final ApiService apiService;
  final LocalMediaStore localMediaStore = LocalMediaStore();

  LocalMeshServer? _localMeshServer;
  LocalMeshDiscovery? _localMeshDiscovery;

  String _deviceId = "node_${DateTime.now().millisecondsSinceEpoch}";
  String _deviceName = "Mobile Crew Node";

  List<Song> _localSongs = [];
  List<PeerNode> _peerNodes = [];
  List<PeerNode> _hubPeers = [];
  int _peerSyncGeneration = 0;
  int _refreshGeneration = 0;
  final Map<String, Future<bool>> _activePins = {};
  final List<Song> _peerSongs = [];
  List<VideoItem> _localVideos = [];
  final List<VideoItem> _peerVideos = [];

  // User Customizations & Filter State
  final Set<String> _hiddenSongIds = {};
  final Set<String> _hiddenVideoIds = {};
  final Set<String> _favoriteIds = {};
  final List<Playlist> _playlists = [];

  MeshFilter _filter = MeshFilter.all;
  String _searchQuery = "";
  bool _isLoading = false;

  HypermeshProvider({required this.apiService}) {
    _initStandaloneMesh();
  }

  List<Song> get localSongs => _localSongs;
  List<VideoItem> get localVideos => _localVideos;
  List<PeerNode> get peerNodes => _peerNodes;
  List<Playlist> get playlists => _playlists;
  Set<String> get favoriteIds => _favoriteIds;
  MeshFilter get filter => _filter;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get localNodeIp => _localMeshServer?.localIp ?? "127.0.0.1";
  int get localNodePort => _localMeshServer?.port ?? 8080;
  bool get isServerRunning => _localMeshServer?.isRunning ?? false;
  int get sharedFilesCount => localMediaStore.sharedFiles.length;
  List<String> get sharedFolders => localMediaStore.sharedFolders;
  String get localShareUrl => "http://$localNodeIp:$localNodePort";
  bool get isBackgroundServiceEnabled => _isBackgroundServiceEnabled;
  bool _isBackgroundServiceEnabled = false;
  bool _serverDownloaderAvailable = false;
  bool get serverDownloaderAvailable => _serverDownloaderAvailable;

  UpdateInfo? _availableUpdate;
  UpdateInfo? get availableUpdate => _availableUpdate;

  bool get isAdmin => apiService.isAdmin;
  bool isLocalSharedMedia(String id) => localMediaStore.getFileById(id) != null;

  Future<bool> verifyAdminPassword(String password) async {
    final success = await apiService.verifyAdminPassword(password);
    notifyListeners();
    return success;
  }

  Future<void> logoutAdmin() async {
    await apiService.setAdminToken(null);
    notifyListeners();
  }

  Future<bool> deleteMediaPermanently(String mediaId) async {
    if (isLocalSharedMedia(mediaId)) {
      await removeSharedFile(mediaId);
      return true;
    }

    final serverDeleted = await apiService.deleteMediaOnServer(mediaId);
    await removeSongForMe(mediaId);
    await removeVideoForMe(mediaId);
    await refreshLibrary();
    return serverDeleted;
  }

  int get totalLocalCount => _localSongs.length;
  int get totalPeerCount => _peerSongs.where((s) => !_hiddenSongIds.contains(s.id)).length;
  int get totalHypermeshCount => totalLocalCount + totalPeerCount;
  int get hiddenCount => _hiddenSongIds.length + _hiddenVideoIds.length;

  int get totalLocalVideosCount => _localVideos.length;
  int get totalPeerVideosCount => _peerVideos.where((v) => !_hiddenVideoIds.contains(v.id)).length;
  int get totalHypermeshVideosCount => totalLocalVideosCount + totalPeerVideosCount;

  // --- FILTERED SONGS ---
  List<Song> get filteredSongs {
    List<Song> sourceList;
    switch (_filter) {
      case MeshFilter.all:
        sourceList = [
          ..._localSongs,
          ..._peerSongs.where((s) => !_hiddenSongIds.contains(s.id))
        ];
        break;
      case MeshFilter.mine:
        sourceList = _localSongs;
        break;
      case MeshFilter.peers:
        sourceList = _peerSongs.where((s) => !_hiddenSongIds.contains(s.id)).toList();
        break;
      case MeshFilter.favorites:
        sourceList = [
          ..._localSongs,
          ..._peerSongs.where((s) => !_hiddenSongIds.contains(s.id))
        ].where((s) => _favoriteIds.contains(s.id) || s.isFavorite).toList();
        break;
    }

    if (_searchQuery.trim().isEmpty) {
      return sourceList;
    }

    final query = _searchQuery.toLowerCase();
    return sourceList.where((song) {
      return song.title.toLowerCase().contains(query) ||
          song.artist.toLowerCase().contains(query) ||
          song.album.toLowerCase().contains(query);
    }).toList();
  }

  // --- FILTERED VIDEOS ---
  List<VideoItem> get filteredVideos {
    List<VideoItem> sourceList;
    switch (_filter) {
      case MeshFilter.all:
        sourceList = [
          ..._localVideos,
          ..._peerVideos.where((v) => !_hiddenVideoIds.contains(v.id))
        ];
        break;
      case MeshFilter.mine:
        sourceList = _localVideos;
        break;
      case MeshFilter.peers:
        sourceList = _peerVideos.where((v) => !_hiddenVideoIds.contains(v.id)).toList();
        break;
      case MeshFilter.favorites:
        sourceList = [
          ..._localVideos,
          ..._peerVideos.where((v) => !_hiddenVideoIds.contains(v.id))
        ].where((v) => _favoriteIds.contains(v.id) || v.isFavorite).toList();
        break;
    }

    if (_searchQuery.trim().isEmpty) {
      return sourceList;
    }

    final query = _searchQuery.toLowerCase();
    return sourceList.where((video) {
      return video.title.toLowerCase().contains(query) ||
          video.resolution.toLowerCase().contains(query);
    }).toList();
  }

  void setFilter(MeshFilter newFilter) {
    _filter = newFilter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // --- INITIALIZE EMBEDDED STANDALONE MESH ---
  Future<void> _initStandaloneMesh() async {
    await apiService.init();
    await localMediaStore.init();

    final prefs = await SharedPreferences.getInstance();

    // Load or generate persistent device ID
    var savedId = prefs.getString('mesh_device_id');
    if (savedId == null || savedId.isEmpty) {
      savedId = "phone_${DateTime.now().millisecondsSinceEpoch}";
      await prefs.setString('mesh_device_id', savedId);
    }
    _deviceId = savedId;

    // Load or set device name from verified auth email
    final savedEmail = prefs.getString('auth_user_email');
    final savedName = prefs.getString('mesh_device_name');
    if (savedName != null && savedName.isNotEmpty) {
      _deviceName = savedName;
    } else if (savedEmail != null && savedEmail.contains('@')) {
      _deviceName = savedEmail.split('@')[0];
      await prefs.setString('mesh_device_name', _deviceName);
    }

    // 1. Start Embedded HTTP Server
    _localMeshServer = LocalMeshServer(
      mediaStore: localMediaStore,
      deviceId: _deviceId,
      deviceName: _deviceName,
    );
    await _localMeshServer!.start();

    // 2. Start UDP Discovery Beacon & Listener
    _localMeshDiscovery = LocalMeshDiscovery(
      deviceId: _deviceId,
      deviceName: _deviceName,
      serverPort: _localMeshServer!.port,
      musicCount: localMediaStore.sharedSongs.length,
      videoCount: localMediaStore.sharedVideos.length,
      onPeersChanged: (discovered) {
        _onDiscoveredPeersChanged(discovered);
      },
    );
    await _localMeshDiscovery!.start();

    // 3. Load user preferences & refresh
    await _loadPreferences();
    _isBackgroundServiceEnabled = await BackgroundMeshService.isEnabled();
    if (_isBackgroundServiceEnabled) {
      await BackgroundMeshService.startService(
        filesCount: localMediaStore.sharedFiles.length,
        peersCount: _peerNodes.length,
      );
    }
    await refreshLibrary();
  }

  void _onDiscoveredPeersChanged(List<PeerNode> discovered) {
    _mergePeers(discovered);
    _updateBackgroundNotification();
    _syncPeerMedia();
  }

  Future<void> setBackgroundServiceEnabled(bool enable) async {
    _isBackgroundServiceEnabled = enable;
    await BackgroundMeshService.setEnabled(enable);
    await BackgroundMeshService.setWasAsked(true);

    if (enable) {
      await BackgroundMeshService.startService(
        filesCount: localMediaStore.sharedFiles.length,
        peersCount: _peerNodes.length,
      );
    } else {
      await BackgroundMeshService.stopService();
    }
    notifyListeners();
  }

  void _updateBackgroundNotification() {
    if (_isBackgroundServiceEnabled) {
      BackgroundMeshService.updateService(
        filesCount: localMediaStore.sharedFiles.length,
        peersCount: _peerNodes.length,
      );
    }
  }

  Future<void> checkAndPromptBackgroundSharing(BuildContext context) async {
    if (!BackgroundMeshService.isSupportedPlatform) return;
    final wasAsked = await BackgroundMeshService.wasAsked();
    if (!wasAsked && context.mounted) {
      final approved = await BackgroundSharingDialog.show(context);
      await setBackgroundServiceEnabled(approved);
    }
  }

  Future<void> updateDeviceName(String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) return;

    _deviceName = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mesh_device_name', _deviceName);

    _localMeshServer?.deviceName = _deviceName;
    _localMeshDiscovery?.deviceName = _deviceName;
    notifyListeners();
  }

  // --- FILE & FOLDER PICKER FOR SHARING ---
  Future<({String? folderPath, int addedCount, String? error})> pickLocalFolder() async {
    final res = await localMediaStore.pickAndAddFolder();
    if (res.folderPath != null) {
      _localMeshDiscovery?.updateMediaCounts(
        music: localMediaStore.sharedSongs.length,
        video: localMediaStore.sharedVideos.length,
      );
      await refreshLibrary();
      _updateBackgroundNotification();
    }
    return (folderPath: res.folderPath, addedCount: res.added.length, error: res.error);
  }

  Future<int> rescanLocalFolders() async {
    final added = await localMediaStore.rescanAllFolders();
    _localMeshDiscovery?.updateMediaCounts(
      music: localMediaStore.sharedSongs.length,
      video: localMediaStore.sharedVideos.length,
    );
    await refreshLibrary();
    _updateBackgroundNotification();
    return added;
  }

  Future<void> removeLocalFolder(String folderPath) async {
    await localMediaStore.removeFolder(folderPath);
    _localMeshDiscovery?.updateMediaCounts(
      music: localMediaStore.sharedSongs.length,
      video: localMediaStore.sharedVideos.length,
    );
    await refreshLibrary();
    _updateBackgroundNotification();
  }

  Future<({bool ok, String message, PeerNode? peer})> connectPeerByQrOrUrl(String rawInput) async {
    final parsed = parsePeerAddress(rawInput);
    if (parsed == null) {
      return (ok: false, message: "Invalid peer QR code or IP address.", peer: null);
    }

    final (host, port) = parsed;
    if (host == localNodeIp && port == localNodePort) {
      return (ok: false, message: "That is this device's own QR code.", peer: null);
    }

    try {
      final uri = Uri.parse("http://$host:$port/api/info");
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return (
          ok: false,
          message: "Peer returned HTTP ${response.statusCode}. Make sure both phones are on the same Wi-Fi or Hotspot.",
          peer: null,
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final peerId = data['id']?.toString() ?? "manual_${host.replaceAll('.', '_')}_$port";
      final peerName = data['name']?.toString() ?? "Mobile Peer";
      final musicCount = (data['music_count'] is num) ? (data['music_count'] as num).toInt() : 0;
      final videoCount = (data['video_count'] is num) ? (data['video_count'] as num).toInt() : 0;
      final appVersion = data['app_version']?.toString() ?? '1.0.0';
      final buildNumber = (data['build_number'] is num) ? (data['build_number'] as num).toInt() : 1;

      final peer = PeerNode(
        id: peerId,
        name: peerName,
        host: host,
        port: port,
        musicCount: musicCount,
        videoCount: videoCount,
        isOnline: true,
        lastSeen: DateTime.now(),
        appVersion: appVersion,
        buildNumber: buildNumber,
      );

      _localMeshDiscovery?.addManualPeerNode(peer);
      _mergePeers(_localMeshDiscovery?.peers ?? []);
      await _syncPeerMedia();
      _updateBackgroundNotification();
      notifyListeners();

      return (
        ok: true,
        message: "Connected to $peerName ($musicCount songs, $videoCount videos)",
        peer: peer,
      );
    } catch (e) {
      return (
        ok: false,
        message: "Could not reach http://$host:$port. Ensure both devices are on the same Wi-Fi/Hotspot.",
        peer: null,
      );
    }
  }

  static (String, int)? parsePeerAddress(String rawInput) {
    var text = rawInput.trim();
    if (text.isEmpty) return null;

    if (text.startsWith('{')) {
      try {
        final map = json.decode(text) as Map<String, dynamic>;
        final h = map['host']?.toString().trim() ?? '';
        final p = (map['port'] is num) ? (map['port'] as num).toInt() : 8080;
        if (h.isNotEmpty) return (h, p);
      } catch (_) {}
    }

    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'http://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : 8080;
    return (uri.host, port);
  }

  Future<int> pickLocalFiles({required bool isVideo}) async {
    final added = await localMediaStore.pickAndAddFiles(isVideo: isVideo);
    if (added.isNotEmpty) {
      _localMeshDiscovery?.updateMediaCounts(
        music: localMediaStore.sharedSongs.length,
        video: localMediaStore.sharedVideos.length,
      );
      await refreshLibrary();
      _updateBackgroundNotification();
    }
    return added.length;
  }

  Future<void> removeSharedFile(String id) async {
    await localMediaStore.removeFile(id);
    _localMeshDiscovery?.updateMediaCounts(
      music: localMediaStore.sharedSongs.length,
      video: localMediaStore.sharedVideos.length,
    );
    await refreshLibrary();
    _updateBackgroundNotification();
  }

  // --- PINNING (COPYING PEER MEDIA TO LOCAL STORAGE) ---
  Future<bool> pinPeerMedia(Object item, {void Function(double)? onProgress}) async {
    final (id, title, source, asset, duration, resolution, isVideo) = switch (item) {
      Song() => (item.id, item.title, item.sourceNodeHost, item.demoAsset, item.duration, '', false),
      VideoItem() => (item.id, item.title, item.sourceNodeHost, item.demoAsset, item.duration, item.resolution, true),
      _ => ('', '', '', null, 0.0, '', false),
    };
    if (id.isEmpty || isLocalSharedMedia(id)) return false;
    final host = source.isEmpty ? apiService.hostUrl : source;
    final cleanHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    final url = "$cleanHost/api/download/${Uri.encodeComponent(id)}";
    return _activePins.putIfAbsent(url, () async {
      try {
        return await _savePin(url, title, isVideo, asset, duration, resolution, onProgress);
      } finally {
        _activePins.remove(url);
      }
    });
  }

  Future<bool> saveDownloadedTaskToPhone(
    Map<String, dynamic> task, {
    void Function(double)? onProgress,
  }) async {
    final url = apiService.resolveDownloadFileUrl(task);
    if (url == null || url.isEmpty) return false;
    final rawTitle = (task['title'] as String?)?.trim();
    final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : 'Downloaded Media';
    final format = ApiService.normalizeDownloadFormat(task['format']?.toString() ?? 'audio');
    final isVideo = format == 'video';
    final duration = (task['duration'] is num) ? (task['duration'] as num).toDouble() : 0.0;
    final resolution = isVideo ? '1080p FHD' : '';

    return _activePins.putIfAbsent(url, () async {
      try {
        return await _savePin(url, title, isVideo, null, duration, resolution, onProgress);
      } finally {
        _activePins.remove(url);
      }
    });
  }

  Future<bool> _savePin(String url, String title, bool isVideo, String? asset,
      double duration, String resolution, void Function(double)? onProgress) async {
    final savedPath = await localMediaStore.pinMediaLocally(
      downloadUrl: url,
      fileName: "$title.${isVideo ? 'mp4' : asset == null ? 'mp3' : 'm4a'}",
      isVideo: isVideo,
      asset: asset,
      duration: duration,
      resolution: resolution,
      onProgress: onProgress,
    );

    if (savedPath != null) {
      _localMeshDiscovery?.updateMediaCounts(
        music: localMediaStore.sharedSongs.length,
        video: localMediaStore.sharedVideos.length,
      );
      await refreshLibrary();
      return true;
    }
    return false;
  }

  // --- REFRESH LIBRARY ---
  Future<void> refreshLibrary() async {
    final generation = ++_refreshGeneration;
    _isLoading = true;
    notifyListeners();

    try {
      final currentServerUrl = _localMeshServer?.serverUrl ?? apiService.hostUrl;

      // 1. Build Local Songs & Videos from embedded storage
      final localSongsFromDevice = localMediaStore.toSongs(
        nodeName: _deviceName,
        hostUrl: currentServerUrl,
        ownerId: _deviceId,
      );

      final localVideosFromDevice = localMediaStore.toVideos(
        nodeName: _deviceName,
        hostUrl: currentServerUrl,
        ownerId: _deviceId,
      );

      final results = await (
        apiService.fetchLocalSongs(),
        apiService.fetchLocalVideos(),
        apiService.fetchDiscoveredPeers(),
        apiService.checkDownloaderAvailable(),
      ).wait;
      if (generation != _refreshGeneration) return;
      final (hubSongs, hubVideos, hubPeers, downloaderAvailable) = results;
      _localSongs = [...localSongsFromDevice, ...hubSongs];
      _localVideos = [...localVideosFromDevice, ...hubVideos];
      _hubPeers = hubPeers;
      _serverDownloaderAvailable = downloaderAvailable;
      _mergePeers(_localMeshDiscovery?.peers ?? []);
    
      // 3. Aggregate Peer Songs & Videos
      await _syncPeerMedia();
      if (generation != _refreshGeneration) return;
      _updateBackgroundNotification();

      // 4. Check for updates (Option C: Peer Mesh, Option B: Server OTA)
      final update = apiService.isDemo ? null :
          AppUpdateService.checkPeerUpdates(_peerNodes) ??
          await AppUpdateService.checkServerUpdate(apiService.hostUrl);
      if (generation == _refreshGeneration) _availableUpdate = update;
    } catch (_) {}

    if (generation != _refreshGeneration) return;
    _isLoading = false;
    notifyListeners();
  }

  Future<UpdateInfo?> checkForUpdates() async {
    final peerUp = AppUpdateService.checkPeerUpdates(_peerNodes);
    if (peerUp != null) {
      _availableUpdate = peerUp;
      notifyListeners();
      return peerUp;
    }

    final serverUp = await AppUpdateService.checkServerUpdate(apiService.hostUrl);
    _availableUpdate = serverUp;
    notifyListeners();
    return serverUp;
  }

  void _mergePeers(List<PeerNode> discovered) {
    _peerNodes = {
      for (final peer in _hubPeers) peer.id: peer,
      for (final peer in discovered) peer.id: peer,
    }.values.where((peer) => peer.id != _deviceId).toList();
  }

  Future<void> _syncPeerMedia() async {
    final generation = ++_peerSyncGeneration;
    final media = await Future.wait(_peerNodes.where((peer) => peer.isOnline).map(
      (peer) => (
        apiService.fetchPeerSongs(peer),
        apiService.fetchPeerVideos(peer),
      ).wait,
    ));
    if (generation != _peerSyncGeneration) return;
    _peerSongs
      ..clear()
      ..addAll(media.expand((item) => item.$1));
    _peerVideos
      ..clear()
      ..addAll(media.expand((item) => item.$2));
    notifyListeners();
  }

  // --- REMOVE FOR ME (HIDE UNWANTED PEER SONGS/VIDEOS) ---
  Future<void> removeSongForMe(String songId) async {
    _hiddenSongIds.add(songId);
    await _savePreferences();
    notifyListeners();
  }

  Future<void> removeVideoForMe(String videoId) async {
    _hiddenVideoIds.add(videoId);
    await _savePreferences();
    notifyListeners();
  }

  Future<void> restoreHiddenItems() async {
    _hiddenSongIds.clear();
    _hiddenVideoIds.clear();
    await _savePreferences();
    notifyListeners();
  }

  // --- FAVORITES ---
  bool isFavorite(String id) => _favoriteIds.contains(id);

  Future<void> toggleFavorite(String id) async {
    if (_favoriteIds.contains(id)) {
      _favoriteIds.remove(id);
    } else {
      _favoriteIds.add(id);
    }
    await _savePreferences();
    apiService.toggleFavoriteOnServer(id);
    notifyListeners();
  }

  // --- PLAYLISTS ---
  Future<void> createPlaylist(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;

    final playlist = Playlist(
      id: "pl_${DateTime.now().millisecondsSinceEpoch}",
      name: clean,
    );
    _playlists.add(playlist);
    await _savePreferences();
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, String songId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1 && !_playlists[idx].songIds.contains(songId)) {
      _playlists[idx].songIds.add(songId);
      await _savePreferences();
      notifyListeners();
    }
  }

  // Legacy replication for PC server
  Future<bool> saveToHub(String shareId) async {
    if (apiService.isDemo) return false;
    final saved = await apiService.copyPeerMediaToServer(shareId);
    if (saved) await refreshLibrary();
    return saved;
  }

  // --- PERSISTENCE ---
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final hiddenS = prefs.getStringList('hidden_song_ids') ?? [];
    _hiddenSongIds.addAll(hiddenS);

    final hiddenV = prefs.getStringList('hidden_video_ids') ?? [];
    _hiddenVideoIds.addAll(hiddenV);

    final favs = prefs.getStringList('favorite_ids') ?? [];
    _favoriteIds.addAll(favs);

    final plsJson = prefs.getStringList('custom_playlists') ?? [];
    _playlists.clear();
    for (final str in plsJson) {
      try {
        _playlists.add(Playlist.fromJson(json.decode(str)));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hidden_song_ids', _hiddenSongIds.toList());
    await prefs.setStringList('hidden_video_ids', _hiddenVideoIds.toList());
    await prefs.setStringList('favorite_ids', _favoriteIds.toList());

    final plsJson = _playlists.map((p) => json.encode(p.toJson())).toList();
    await prefs.setStringList('custom_playlists', plsJson);
  }

  @override
  void dispose() {
    _refreshGeneration++;
    _peerSyncGeneration++;
    _localMeshServer?.stop();
    _localMeshDiscovery?.stop();
    super.dispose();
  }
}
