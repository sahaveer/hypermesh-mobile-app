import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/video_item.dart';
import '../providers/hypermesh_provider.dart';
import '../providers/player_provider.dart';
import '../screens/video_player_screen.dart';
import '../services/background_mesh_service.dart';
import '../services/phone_download_manager.dart';
import '../theme/app_theme.dart';
import 'now_playing_sheet.dart';

class ServerDownloaderDialog extends StatefulWidget {
  final String? initialUrl;

  const ServerDownloaderDialog({super.key, this.initialUrl});

  static Future<void> show(BuildContext context, {String? initialUrl}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServerDownloaderDialog(initialUrl: initialUrl),
    );
  }

  @override
  State<ServerDownloaderDialog> createState() => _ServerDownloaderDialogState();
}

class _ServerDownloaderDialogState extends State<ServerDownloaderDialog> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _clipStartController = TextEditingController();
  final TextEditingController _clipEndController = TextEditingController();
  final TextEditingController _proxyController = TextEditingController();
  String _selectedFormat = "audio"; // "audio" or "video"
  String _selectedQuality = "best"; // "best", "4k", "1080p", "720p"
  String _selectedDestination = "server"; // "server", "client", or "phone_direct"
  bool _downloadPlaylist = false;
  bool _downloadSubtitles = false;
  bool _showAdvanced = false;
  String? _clipboardSuggestion;
  bool _isSubmitting = false;
  bool _isSearching = false;
  String? _statusFeedback;
  bool _feedbackIsError = false;
  Timer? _pollingTimer;
  List<Map<String, dynamic>> _tasks = [];

  List<Map<String, dynamic>> _localSearchMatches = [];
  List<Map<String, dynamic>> _youtubeSearchResults = [];
  bool _hasSearched = false;
  String _lastSearchQuery = '';

  final Set<String> _knownCompletedIds = {};
  final Set<String> _knownFailedIds = {};
  final Set<String> _requestedClientTaskIds = {};
  final Set<String> _autoPlayTaskIds = {};
  final Set<String> _savingTaskIds = {};
  final Set<String> _savedTaskIds = {};
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    final hypermesh = context.read<HypermeshProvider>();
    hypermesh.phoneDownloader.init();
    if (widget.initialUrl != null && widget.initialUrl!.trim().isNotEmpty) {
      final clean = widget.initialUrl!.trim();
      _urlController.text = clean;
      if (PhoneDownloadManager.isDirectDownloadUrl(clean) && !hypermesh.serverDownloaderAvailable) {
        _selectedDestination = "phone_direct";
      }
    } else {
      _detectClipboardLink();
    }
    _fetchTasks();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _fetchTasks();
    });
  }

  Future<void> _detectClipboardLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted || text.isEmpty) return;
      if (_isMediaUrl(text) && text != _urlController.text.trim()) {
        setState(() {
          _clipboardSuggestion = text;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _urlController.dispose();
    _clipStartController.dispose();
    _clipEndController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    final hypermesh = context.read<HypermeshProvider>();
    final tasks = await hypermesh.apiService.fetchDownloadStatus();
    if (!mounted) return;

    bool shouldRefreshLibrary = false;
    final tasksToAutoSave = <Map<String, dynamic>>[];
    final tasksToAutoPlay = <Map<String, dynamic>>[];

    for (final task in tasks) {
      final id = task['id']?.toString() ?? '';
      final status = (task['status'] as String? ?? '').toLowerCase();
      final title = task['title']?.toString() ?? 'Download';
      final isDone = status == 'completed' || status == 'finished';
      final isErr = status == 'failed' || status == 'error';
      if (id.isNotEmpty && isErr && !_knownFailedIds.contains(id)) {
        _knownFailedIds.add(id);
        if (_initialLoadDone) {
          BackgroundMeshService.showDownloadComplete(
            id: id,
            title: title,
            success: false,
            message: task['error']?.toString() ?? 'Server download failed',
          );
        }
      }
      if (id.isEmpty || !isDone) continue;

      if (!_knownCompletedIds.contains(id)) {
        _knownCompletedIds.add(id);
        if (_initialLoadDone) {
          BackgroundMeshService.showDownloadComplete(
            id: id,
            title: title,
            success: true,
            message: 'Ready on ${(task['destination'] ?? 'server') == 'client' ? 'phone' : 'server'}',
          );
          final dest = (task['destination'] as String? ?? 'server').toLowerCase();
          if (dest == 'server') {
            shouldRefreshLibrary = true;
            if (_autoPlayTaskIds.remove(id)) {
              tasksToAutoPlay.add(task);
            }
          } else if (dest == 'client' &&
              (_requestedClientTaskIds.contains(id) || task['owner_id'] == hypermesh.deviceId) &&
              !_savingTaskIds.contains(id) &&
              !_savedTaskIds.contains(id)) {
            tasksToAutoSave.add(task);
          }
        }
      }
    }

    _initialLoadDone = true;

    setState(() {
      _tasks = tasks;
    });

    if (shouldRefreshLibrary) {
      await hypermesh.refreshLibrary();
    }
    for (final task in tasksToAutoSave) {
      _saveTaskToPhone(task);
    }
    if (tasksToAutoPlay.isNotEmpty && mounted) {
      await _autoPlayCompletedTask(tasksToAutoPlay.first);
    }
  }

  Future<void> _autoPlayCompletedTask(Map<String, dynamic> task) async {
    final songId = task['song_id']?.toString() ?? '';
    if (songId.isEmpty || !mounted) return;
    final hypermesh = context.read<HypermeshProvider>();
    final item = await hypermesh.apiService.fetchSongById(songId);
    if (item == null || !mounted) return;
    await _playServerItem(item);
  }

  Future<void> _playServerItem(Map<String, dynamic> item) async {
    if (!mounted) return;
    final hypermesh = context.read<HypermeshProvider>();
    final mediaType = (item['media_type']?.toString() ?? 'audio').toLowerCase();
    final hostUrl = hypermesh.apiService.hostUrl;
    final id = item['id']?.toString() ?? '';
    final title = item['title']?.toString() ?? 'Unknown';
    final duration = (item['duration'] is num) ? (item['duration'] as num).toDouble() : 0.0;

    if (mediaType == 'video') {
      final video = VideoItem(
        id: id,
        title: title,
        duration: duration,
        filesize: (item['filesize'] is num) ? (item['filesize'] as num).toInt() : 0,
        resolution: item['resolution']?.toString() ?? '1080p FHD',
        ownerId: item['owner_id']?.toString() ?? 'host',
        ownerName: item['owner_name']?.toString() ?? 'Server',
        sourceNodeName: item['owner_name']?.toString() ?? 'Server',
        sourceNodeHost: hostUrl,
        isPeer: false,
      );
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(video: video, hostUrl: hostUrl),
        ),
      );
      return;
    }

    PlayerProvider? player;
    try {
      player = context.read<PlayerProvider>();
    } catch (_) {
      player = null;
    }

    final song = Song(
      id: id,
      title: title,
      artist: item['artist']?.toString() ?? 'Server',
      album: item['album']?.toString() ?? '',
      duration: duration,
      ownerId: item['owner_id']?.toString() ?? 'host',
      ownerName: item['owner_name']?.toString() ?? 'Server',
      sourceNodeName: item['owner_name']?.toString() ?? 'Server',
      sourceNodeHost: hostUrl,
      isPeer: false,
    );

    if (player != null) {
      await player.playSong(song, [song, ...hypermesh.localSongs]);
      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.pop();
      showModalBottomSheet(
        context: nav.context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => NowPlayingSheet(song: song),
      );
    } else {
      setState(() {
        _feedbackIsError = false;
        _statusFeedback = "Ready on server: $title";
      });
    }
  }

  Future<void> _saveTaskToPhone(Map<String, dynamic> task) async {
    final id = task['id']?.toString() ?? '';
    if (id.isEmpty || _savingTaskIds.contains(id)) return;

    setState(() {
      _savingTaskIds.add(id);
    });

    final hypermesh = context.read<HypermeshProvider>();
    final saved = await hypermesh.saveDownloadedTaskToPhone(task);
    if (!mounted) return;

    setState(() {
      _savingTaskIds.remove(id);
      if (saved) {
        _savedTaskIds.add(id);
        _feedbackIsError = false;
        _statusFeedback = "Saved '${task['title'] ?? 'media'}' to your phone!";
      } else {
        _feedbackIsError = true;
        _statusFeedback = "Could not download file to phone storage.";
      }
    });
  }

  List<Map<String, dynamic>> _findInMemoryLibraryMatches(HypermeshProvider hypermesh, String query) {
    final tokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];

    final matches = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    for (final s in hypermesh.localSongs) {
      final hay = '${s.title} ${s.artist} ${s.album}'.toLowerCase();
      if (tokens.every((t) => hay.contains(t)) && seenIds.add(s.id)) {
        matches.add({
          'id': s.id,
          'title': s.title,
          'artist': s.artist,
          'album': s.album,
          'media_type': 'audio',
          'duration': s.duration,
          'owner_name': s.sourceNodeName,
        });
      }
    }
    for (final v in hypermesh.localVideos) {
      final hay = '${v.title} ${v.resolution}'.toLowerCase();
      if (tokens.every((t) => hay.contains(t)) && seenIds.add(v.id)) {
        matches.add({
          'id': v.id,
          'title': v.title,
          'artist': 'Server Video',
          'album': '',
          'media_type': 'video',
          'duration': v.duration,
          'resolution': v.resolution,
          'owner_name': v.sourceNodeName,
        });
      }
    }
    return matches;
  }

  Future<void> _handleSearch({bool includeYoutube = false}) async {
    final query = _urlController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _statusFeedback = null;
      _feedbackIsError = false;
      _lastSearchQuery = query;
    });

    final hypermesh = context.read<HypermeshProvider>();
    final inMemoryMatches = _findInMemoryLibraryMatches(hypermesh, query);

    if (inMemoryMatches.isNotEmpty && !includeYoutube) {
      setState(() {
        _isSearching = false;
        _hasSearched = true;
        _localSearchMatches = inMemoryMatches;
        _youtubeSearchResults = [];
      });
      return;
    }

    final res = await hypermesh.apiService.searchDownloader(
      query: query,
      limit: 8,
      includeYoutube: includeYoutube,
      clientId: hypermesh.deviceId,
    );
    if (!mounted) return;

    if (res['ok'] == true) {
      final serverLocal = (res['local_matches'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final mergedLocal = serverLocal.isNotEmpty ? serverLocal : inMemoryMatches;
      final ytResults = (mergedLocal.isNotEmpty && !includeYoutube)
          ? <Map<String, dynamic>>[]
          : (res['youtube_results'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

      setState(() {
        _isSearching = false;
        _hasSearched = true;
        _localSearchMatches = mergedLocal;
        _youtubeSearchResults = ytResults;
      });
    } else {
      setState(() {
        _isSearching = false;
        _hasSearched = true;
        _localSearchMatches = inMemoryMatches;
        _youtubeSearchResults = [];
        _feedbackIsError = true;
        _statusFeedback = res['error']?.toString() ?? 'Search failed.';
      });
    }
  }

  Future<void> _enqueueUrl(
    String url, {
    String? destinationOverride,
    bool autoPlay = false,
    bool clearInput = false,
  }) async {
    final dest = destinationOverride ?? _selectedDestination;
    final hypermesh = context.read<HypermeshProvider>();

    if (dest == 'phone_direct') {
      setState(() {
        _isSubmitting = true;
        _statusFeedback = null;
        _feedbackIsError = false;
      });
      try {
        await hypermesh.phoneDownloader.startDownload(
          url,
          isVideo: _selectedFormat == 'video',
        );
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          if (clearInput) _urlController.clear();
          _feedbackIsError = false;
          _statusFeedback = "Direct phone download started!";
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _feedbackIsError = true;
          _statusFeedback = "Could not start direct phone download: $e";
        });
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusFeedback = null;
      _feedbackIsError = false;
    });

    final res = await hypermesh.apiService.startServerDownload(
      url: url,
      format: _selectedFormat,
      quality: _selectedFormat == "audio" ? "best" : _selectedQuality,
      destination: dest,
      clientId: hypermesh.deviceId,
      deviceName: hypermesh.deviceName,
      clipStart: _clipStartController.text.trim(),
      clipEnd: _clipEndController.text.trim(),
      subtitles: _downloadSubtitles,
      downloadPlaylist: _downloadPlaylist,
      proxy: _proxyController.text.trim(),
    );

    if (!mounted) return;

    final ok = res['ok'] == true;
    final taskId = res['task_id']?.toString();
    if (ok && taskId != null) {
      if (dest == 'client') {
        _requestedClientTaskIds.add(taskId);
      } else if (autoPlay) {
        _autoPlayTaskIds.add(taskId);
      }
    }

    setState(() {
      _isSubmitting = false;
      if (ok) {
        if (clearInput) _urlController.clear();
        _feedbackIsError = false;
        _statusFeedback = autoPlay
            ? "Downloading on server — will play automatically when ready!"
            : dest == 'client'
                ? "Downloading on server — will save to your phone when ready!"
                : "Download started on your personal server!";
      } else {
        _feedbackIsError = true;
        _statusFeedback = res['error']?.toString() ??
            "Failed to start download. Check your server connection.";
      }
    });

    await _fetchTasks();
  }

  static final RegExp _bareMediaDomainPattern = RegExp(
    r'^(?:www\.)?(?:youtube\.com|youtu\.be|music\.youtube\.com|open\.spotify\.com|instagram\.com|tiktok\.com|vt\.tiktok\.com|vm\.tiktok\.com|soundcloud\.com|vimeo\.com|x\.com|twitter\.com|facebook\.com|fb\.watch)\/\S+$',
    caseSensitive: false,
  );

  bool _isMediaUrl(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty || clean.contains(RegExp(r'\s'))) return false;
    final lower = clean.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('spotify:')) {
      return true;
    }
    return _bareMediaDomainPattern.hasMatch(clean);
  }

  String _normalizeMediaUrl(String raw) {
    final clean = raw.trim();
    final lower = clean.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('spotify:')) {
      return clean;
    }
    return 'https://$clean';
  }

  Future<void> _handleStartDownload() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;
    if (!_isMediaUrl(raw)) {
      await _handleSearch();
      return;
    }
    await _enqueueUrl(_normalizeMediaUrl(raw), clearInput: true);
  }

  Future<void> _pauseTask(String taskId) async {
    if (taskId.isEmpty) return;
    final hypermesh = context.read<HypermeshProvider>();
    final ok = await hypermesh.apiService.pauseDownload(taskId);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _feedbackIsError = true;
        _statusFeedback = "Could not pause download.";
      });
    }
    await _fetchTasks();
  }

  Future<void> _resumeTask(String taskId) async {
    if (taskId.isEmpty) return;
    final hypermesh = context.read<HypermeshProvider>();
    final ok = await hypermesh.apiService.resumeDownload(taskId);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _feedbackIsError = true;
        _statusFeedback = "Could not resume download.";
      });
    }
    await _fetchTasks();
  }

  Future<void> _deleteTask(String taskId) async {
    if (taskId.isEmpty) return;
    final hypermesh = context.read<HypermeshProvider>();
    final ok = await hypermesh.apiService.deleteDownload(taskId);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _feedbackIsError = true;
        _statusFeedback = "Could not delete download.";
      });
    }
    await _fetchTasks();
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    final taskId = task['id']?.toString() ?? '';
    if (taskId.isEmpty) return;
    final urlCtrl = TextEditingController(text: task['url']?.toString() ?? '');
    final proxyCtrl = TextEditingController(text: task['proxy']?.toString() ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Edit Download Task', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'Download URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: proxyCtrl,
              decoration: const InputDecoration(labelText: 'Optional Proxy (http://host:port)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final hypermesh = context.read<HypermeshProvider>();
      final ok = await hypermesh.apiService.editDownload(
        taskId,
        url: urlCtrl.text.trim(),
        proxy: proxyCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _feedbackIsError = !ok;
          _statusFeedback = ok ? 'Download task updated.' : 'Could not update download task.';
        });
      }
      await _fetchTasks();
    }
    urlCtrl.dispose();
    proxyCtrl.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      setState(() {
        _urlController.text = data!.text!.trim();
        _clipboardSuggestion = null;
      });
    }
  }

  String _formatBytes(num? bytes) {
    final b = (bytes ?? 0).toDouble();
    if (b <= 0) return '';
    if (b < 1024) return '${b.toInt()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(dynamic sec) {
    final total = (sec is num) ? sec.toInt() : 0;
    if (total <= 0) return '';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.cyanAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.download_for_offline, color: AppTheme.cyanAccent, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "WEB MEDIA IMPORTER",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                    Text(
                      "Search server library first, then YouTube",
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Search & URL Input Bar
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textInputAction: TextInputAction.search,
            onSubmitted: (val) {
              if (_isMediaUrl(val)) {
                _handleStartDownload();
              } else {
                _handleSearch();
              }
            },
            decoration: InputDecoration(
              hintText: "Search song/video or paste YouTube/Spotify link...",
              hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              filled: true,
              fillColor: AppTheme.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.search, color: AppTheme.cyanAccent, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent),
                          )
                        : const Icon(Icons.youtube_searched_for, color: AppTheme.cyanAccent, size: 20),
                    tooltip: "Search Server & YouTube",
                    onPressed: _isSearching ? null : () => _handleSearch(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste, color: AppTheme.textSecondary, size: 20),
                    tooltip: "Paste from Clipboard",
                    onPressed: _pasteFromClipboard,
                  ),
                ],
              ),
            ),
          ),
          if (_clipboardSuggestion != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                setState(() {
                  _urlController.text = _clipboardSuggestion!;
                  _clipboardSuggestion = null;
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.cyanAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: AppTheme.cyanAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Clipboard link: $_clipboardSuggestion",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTheme.cyanAccent),
                      ),
                    ),
                    const Text("Tap to fill", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Format Selectors (Audio vs Video)
          Row(
            children: [
              _buildChoiceChip(
                selected: _selectedFormat == "audio",
                label: "Audio (MP3)",
                icon: Icons.music_note,
                onTap: () => setState(() => _selectedFormat = "audio"),
              ),
              const SizedBox(width: 10),
              _buildChoiceChip(
                selected: _selectedFormat == "video",
                label: "Video (MP4)",
                icon: Icons.videocam,
                onTap: () => setState(() => _selectedFormat = "video"),
              ),
            ],
          ),

          if (_selectedFormat == "video") ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _buildChoiceChip(
                  selected: _selectedQuality == "best",
                  label: "Best",
                  icon: Icons.hd,
                  onTap: () => setState(() => _selectedQuality = "best"),
                ),
                const SizedBox(width: 6),
                _buildChoiceChip(
                  selected: _selectedQuality == "4k",
                  label: "4K",
                  icon: Icons.four_k,
                  onTap: () => setState(() => _selectedQuality = "4k"),
                ),
                const SizedBox(width: 6),
                _buildChoiceChip(
                  selected: _selectedQuality == "1080p",
                  label: "1080p",
                  icon: Icons.high_quality,
                  onTap: () => setState(() => _selectedQuality = "1080p"),
                ),
                const SizedBox(width: 6),
                _buildChoiceChip(
                  selected: _selectedQuality == "720p",
                  label: "720p",
                  icon: Icons.sd,
                  onTap: () => setState(() => _selectedQuality = "720p"),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Destination Selector (Server Library vs Server->Phone vs Direct Phone HTTP/M3U8)
          Row(
            children: [
              _buildChoiceChip(
                selected: _selectedDestination == "server",
                label: "Save to Server",
                icon: Icons.dns,
                accent: AppTheme.purpleAccent,
                onTap: () => setState(() => _selectedDestination = "server"),
              ),
              const SizedBox(width: 6),
              _buildChoiceChip(
                selected: _selectedDestination == "client",
                label: "Download to Phone",
                icon: Icons.phone_android,
                accent: AppTheme.emeraldAccent,
                onTap: () => setState(() => _selectedDestination = "client"),
              ),
              const SizedBox(width: 6),
              _buildChoiceChip(
                selected: _selectedDestination == "phone_direct",
                label: "Direct/M3U8",
                icon: Icons.bolt,
                accent: AppTheme.cyanAccent,
                onTap: () => setState(() => _selectedDestination = "phone_direct"),
              ),
            ],
          ),
          if (_selectedDestination != "phone_direct") ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  Icon(_showAdvanced ? Icons.expand_less : Icons.tune, size: 15, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    _showAdvanced ? "Hide Advanced Options" : "Advanced (Playlist, Clip Trim, Subtitles, Proxy)",
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("Playlist", style: TextStyle(fontSize: 12)),
                      value: _downloadPlaylist,
                      onChanged: (v) => setState(() => _downloadPlaylist = v ?? false),
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("Subtitles", style: TextStyle(fontSize: 12)),
                      value: _downloadSubtitles,
                      onChanged: (v) => setState(() => _downloadSubtitles = v ?? false),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _clipStartController,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: "Clip start (0:30)",
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.surfaceLight,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _clipEndController,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: "Clip end (1:45)",
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.surfaceLight,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _proxyController,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: "Optional proxy (http://host:port)",
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),

          // Search & Download Buttons
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.cyanAccent,
                    side: const BorderSide(color: AppTheme.cyanAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isSearching ? null : () => _handleSearch(),
                  icon: _isSearching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent))
                      : const Icon(Icons.search, size: 19),
                  label: Text(
                    _isSearching ? "Searching..." : "Search",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isSubmitting ? null : _handleStartDownload,
                  icon: _isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.cloud_download, size: 20),
                  label: Text(
                    _isSubmitting
                        ? "Starting..."
                        : (_selectedDestination == "client"
                            ? "Download to Phone"
                            : _selectedDestination == "phone_direct"
                                ? "Direct Download"
                                : "Start Server Download"),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),

          if (_statusFeedback != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusFeedback!,
              style: TextStyle(
                color: _feedbackIsError ? Colors.redAccent : AppTheme.emeraldAccent,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(color: AppTheme.border),

          // Scrollable Search Results + Server Queue
          Expanded(
            child: ListView(
              children: [
                if (_hasSearched) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _localSearchMatches.isNotEmpty && _youtubeSearchResults.isEmpty
                              ? "ALREADY ON SERVER (${_localSearchMatches.length})"
                              : "YOUTUBE RESULTS (${_youtubeSearchResults.length})",
                          style: TextStyle(
                            color: _localSearchMatches.isNotEmpty && _youtubeSearchResults.isEmpty
                                ? AppTheme.emeraldAccent
                                : AppTheme.cyanAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_localSearchMatches.isNotEmpty && _youtubeSearchResults.isEmpty)
                            TextButton(
                              onPressed: _isSearching ? null : () => _handleSearch(includeYoutube: true),
                              child: const Text("Search YouTube", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            ),
                          TextButton(
                            onPressed: () => setState(() {
                              _hasSearched = false;
                              _localSearchMatches = [];
                              _youtubeSearchResults = [];
                            }),
                            child: const Text("Clear", style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_localSearchMatches.isEmpty && _youtubeSearchResults.isEmpty && !_isSearching)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "No results found for '$_lastSearchQuery'.",
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                  ..._localSearchMatches.map((item) {
                    final dur = _formatDuration(item['duration']);
                    final isVideo = (item['media_type']?.toString() ?? 'audio') == 'video';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.emeraldAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.emeraldAccent.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(isVideo ? Icons.movie : Icons.music_note, color: AppTheme.emeraldAccent, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['title']?.toString() ?? 'Unknown',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                ),
                                Text(
                                  "${item['artist'] ?? 'Server'}${dur.isNotEmpty ? ' • $dur' : ''} • Ready on Server",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: AppTheme.emeraldAccent),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.emeraldAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _playServerItem(item),
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text("Play", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  }),
                  ..._youtubeSearchResults.map((yt) {
                    final dur = _formatDuration(yt['duration']);
                    final thumb = yt['thumbnail']?.toString();
                    final ytUrl = yt['url']?.toString() ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (thumb != null && thumb.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    thumb,
                                    width: 72,
                                    height: 46,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.ondemand_video, color: AppTheme.cyanAccent),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      yt['title']?.toString() ?? 'YouTube Video',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "${yt['channel'] ?? 'YouTube'}${dur.isNotEmpty ? ' • $dur' : ''}",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.cyanAccent,
                                  side: const BorderSide(color: AppTheme.cyanAccent),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _isSubmitting || ytUrl.isEmpty
                                    ? null
                                    : () => _enqueueUrl(ytUrl),
                                icon: const Icon(Icons.download, size: 15),
                                label: const Text("Download", style: TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.cyanAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _isSubmitting || ytUrl.isEmpty
                                    ? null
                                    : () => _enqueueUrl(ytUrl, destinationOverride: 'server', autoPlay: true),
                                icon: const Icon(Icons.play_arrow, size: 16),
                                label: const Text("Download & Play", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(color: AppTheme.border),
                ],

                // Server Active Tasks Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "SERVER DOWNLOAD QUEUE (${_tasks.length})",
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (_tasks.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          final hypermesh = context.read<HypermeshProvider>();
                          await hypermesh.apiService.clearDownloadHistory();
                          _fetchTasks();
                        },
                        child: const Text("Clear Finished", style: TextStyle(color: AppTheme.cyanAccent, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_tasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        "No active downloads on server.",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                  )
                else
                  ..._tasks.map((task) {
                    final taskId = task['id']?.toString() ?? '';
                    final title = task['title'] as String? ?? task['url'] as String? ?? "Unknown Media";
                    final status = (task['status'] as String? ?? "pending").toLowerCase();
                    final progress = (task['progress'] as num?)?.toDouble() ?? 0.0;
                    final dest = (task['destination'] as String? ?? 'server').toLowerCase();
                    final errorMsg = (task['error'] as String?)?.trim();
                    final songId = task['song_id']?.toString() ?? '';
                    final speedNum = task['speed'] is num ? (task['speed'] as num) : 0;
                    final etaNum = task['eta'] is num ? (task['eta'] as num).toInt() : null;
                    final dlBytes = task['downloaded_bytes'] is num ? (task['downloaded_bytes'] as num) : 0;
                    final totalBytes = task['total_bytes'] is num ? (task['total_bytes'] as num) : 0;
                    final isFinished = status == "finished" || status == "completed";
                    final isError = status == "error" || status == "failed";
                    final isPaused = status == "paused";
                    final isQueued = status == "queued";
                    final isActive = !isFinished && !isError && !isPaused;
                    final isSaving = _savingTaskIds.contains(taskId);
                    final isSaved = _savedTaskIds.contains(taskId);
                    final speedLabel = _formatBytes(speedNum);
                    final sizeLabel = (dlBytes > 0 && totalBytes > 0)
                        ? '${_formatBytes(dlBytes)} / ${_formatBytes(totalBytes)}'
                        : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isError
                              ? Colors.redAccent.withOpacity(0.5)
                              : isPaused
                                  ? Colors.amber.withOpacity(0.5)
                                  : AppTheme.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isFinished
                                    ? Icons.check_circle
                                    : isError
                                        ? Icons.error
                                        : isPaused
                                            ? Icons.pause_circle
                                            : Icons.downloading,
                                color: isFinished
                                    ? AppTheme.emeraldAccent
                                    : isError
                                        ? Colors.redAccent
                                        : isPaused
                                            ? Colors.amber
                                            : AppTheme.cyanAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isError
                                    ? "Failed"
                                    : isPaused
                                        ? "Paused ${progress.toInt()}%"
                                        : isQueued
                                            ? "Queued"
                                            : isFinished
                                                ? "100%"
                                                : "${progress.toInt()}%",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isError
                                      ? Colors.redAccent
                                      : isPaused
                                          ? Colors.amber
                                          : isFinished
                                              ? AppTheme.emeraldAccent
                                              : AppTheme.cyanAccent,
                                ),
                              ),
                              if (isActive)
                                IconButton(
                                  tooltip: "Pause download",
                                  icon: const Icon(Icons.pause, size: 18, color: Colors.amber),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _pauseTask(taskId),
                                ),
                              if (isPaused || isError)
                                IconButton(
                                  tooltip: "Resume download",
                                  icon: const Icon(Icons.play_arrow, size: 18, color: AppTheme.emeraldAccent),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _resumeTask(taskId),
                                ),
                              if (isPaused || isError || isQueued)
                                IconButton(
                                  tooltip: "Edit URL or proxy",
                                  icon: const Icon(Icons.edit, size: 16, color: AppTheme.cyanAccent),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _editTask(task),
                                ),
                              IconButton(
                                tooltip: "Delete download",
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                padding: const EdgeInsets.only(left: 4),
                                constraints: const BoxConstraints(),
                                onPressed: () => _deleteTask(taskId),
                              ),
                            ],
                          ),
                          if (sizeLabel.isNotEmpty || speedLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (sizeLabel.isNotEmpty) sizeLabel,
                                if (speedLabel.isNotEmpty) '$speedLabel/s',
                                if (etaNum != null && etaNum > 0) 'ETA ${etaNum}s',
                              ].join(' • '),
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                            ),
                          ],
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: isFinished ? 1.0 : (progress / 100.0).clamp(0.0, 1.0),
                            backgroundColor: Colors.white10,
                            color: isFinished
                                ? AppTheme.emeraldAccent
                                : isError
                                    ? Colors.redAccent
                                    : isPaused
                                        ? Colors.amber
                                        : AppTheme.cyanAccent,
                            minHeight: 4,
                          ),
                          if (isError && errorMsg != null && errorMsg.isNotEmpty) ...[
                            if (sizeLabel.isNotEmpty || speedLabel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (sizeLabel.isNotEmpty) sizeLabel,
                                if (speedLabel.isNotEmpty) '$speedLabel/s',
                                if (etaNum != null && etaNum > 0) 'ETA ${etaNum}s',
                              ].join(' • '),
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                            ),
                          ],
                          const SizedBox(height: 6),
                            Text(
                              errorMsg,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                            ),
                          ],
                          if (isFinished && dest == 'server' && songId.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.emeraldAccent,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _autoPlayCompletedTask(task),
                                icon: const Icon(Icons.play_arrow, size: 16),
                                label: const Text("Play from Server", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                          if (isFinished && dest == 'client') ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: isSaved ? AppTheme.emeraldAccent : AppTheme.cyanAccent,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: (isSaving || isSaved) ? null : () => _saveTaskToPhone(task),
                                icon: Icon(
                                  isSaved
                                      ? Icons.offline_pin
                                      : isSaving
                                          ? Icons.hourglass_top
                                          : Icons.download_done,
                                  size: 16,
                                ),
                                label: Text(
                                  isSaved
                                      ? "Saved on Phone"
                                      : isSaving
                                          ? "Saving to Phone..."
                                          : "Save to Phone",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                Consumer<HypermeshProvider>(
                  builder: (_, hm, _) {
                    final localTasks = hm.phoneDownloader.tasks;
                    if (localTasks.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: AppTheme.border),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "ON-DEVICE DIRECT / M3U8 (${localTasks.length})",
                              style: const TextStyle(
                                color: AppTheme.cyanAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            TextButton(
                              onPressed: () => hm.phoneDownloader.clearFinished(),
                              child: const Text("Clear Finished", style: TextStyle(color: AppTheme.cyanAccent, fontSize: 12)),
                            ),
                          ],
                        ),
                        ...localTasks.map((lt) {
                          final isDone = lt.status == 'completed';
                          final isErr = lt.status == 'failed';
                          final isPaused = lt.status == 'paused';
                          final isActive = lt.status == 'downloading' || lt.status == 'pending';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isDone ? Icons.offline_pin : isErr ? Icons.error : isPaused ? Icons.pause_circle : Icons.bolt,
                                      size: 18,
                                      color: isDone ? AppTheme.emeraldAccent : isErr ? Colors.redAccent : isPaused ? Colors.amber : AppTheme.cyanAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(lt.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    ),
                                    Text("${lt.progress.toInt()}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    if (isActive)
                                      IconButton(
                                        icon: const Icon(Icons.pause, size: 18, color: Colors.amber),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        constraints: const BoxConstraints(),
                                        onPressed: () => hm.phoneDownloader.pause(lt.id),
                                      ),
                                    if (isPaused || isErr)
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow, size: 18, color: AppTheme.emeraldAccent),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        constraints: const BoxConstraints(),
                                        onPressed: () => hm.phoneDownloader.resume(lt.id),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      padding: const EdgeInsets.only(left: 4),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => hm.phoneDownloader.delete(lt.id),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: isDone ? 1.0 : (lt.progress / 100.0).clamp(0.0, 1.0),
                                  backgroundColor: Colors.white10,
                                  color: isDone ? AppTheme.emeraldAccent : isErr ? Colors.redAccent : isPaused ? Colors.amber : AppTheme.cyanAccent,
                                  minHeight: 4,
                                ),
                                if (lt.speedBytesPerSec > 0 || lt.totalBytes > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (lt.totalBytes > 0) '${_formatBytes(lt.downloadedBytes)} / ${_formatBytes(lt.totalBytes)}',
                                      if (lt.speedBytesPerSec > 0) '${_formatBytes(lt.speedBytesPerSec)}/s',
                                      if (lt.etaSeconds != null && lt.etaSeconds! > 0) 'ETA ${lt.etaSeconds}s',
                                    ].join(' • '),
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                                  ),
                                ],
                                if (isErr && lt.error != null) ...[
                                  const SizedBox(height: 4),
                                  Text(lt.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required bool selected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color accent = AppTheme.cyanAccent,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.15) : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: selected ? accent : AppTheme.textSecondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? accent : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
