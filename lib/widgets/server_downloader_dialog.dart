import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/video_item.dart';
import '../providers/hypermesh_provider.dart';
import '../providers/player_provider.dart';
import '../screens/video_player_screen.dart';
import '../theme/app_theme.dart';
import 'now_playing_sheet.dart';

class ServerDownloaderDialog extends StatefulWidget {
  const ServerDownloaderDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ServerDownloaderDialog(),
    );
  }

  @override
  State<ServerDownloaderDialog> createState() => _ServerDownloaderDialogState();
}

class _ServerDownloaderDialogState extends State<ServerDownloaderDialog> {
  final TextEditingController _urlController = TextEditingController();
  String _selectedFormat = "audio"; // "audio" or "video"
  String _selectedQuality = "best"; // "best", "1080p", "720p"
  String _selectedDestination = "server"; // "server" or "client"
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
  final Set<String> _requestedClientTaskIds = {};
  final Set<String> _autoPlayTaskIds = {};
  final Set<String> _savingTaskIds = {};
  final Set<String> _savedTaskIds = {};
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _fetchTasks();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _urlController.dispose();
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
      final isDone = status == 'completed' || status == 'finished';
      if (id.isEmpty || !isDone) continue;

      if (!_knownCompletedIds.contains(id)) {
        _knownCompletedIds.add(id);
        if (_initialLoadDone) {
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
    setState(() {
      _isSubmitting = true;
      _statusFeedback = null;
      _feedbackIsError = false;
    });

    final hypermesh = context.read<HypermeshProvider>();
    final res = await hypermesh.apiService.startServerDownload(
      url: url,
      format: _selectedFormat,
      quality: _selectedFormat == "audio" ? "best" : _selectedQuality,
      destination: dest,
      clientId: hypermesh.deviceId,
      deviceName: hypermesh.deviceName,
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      setState(() {
        _urlController.text = data!.text!.trim();
      });
    }
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
                const SizedBox(width: 8),
                _buildChoiceChip(
                  selected: _selectedQuality == "1080p",
                  label: "1080p",
                  icon: Icons.high_quality,
                  onTap: () => setState(() => _selectedQuality = "1080p"),
                ),
                const SizedBox(width: 8),
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

          // Destination Selector (Server Library vs This Phone)
          Row(
            children: [
              _buildChoiceChip(
                selected: _selectedDestination == "server",
                label: "Save to Server",
                icon: Icons.dns,
                accent: AppTheme.purpleAccent,
                onTap: () => setState(() => _selectedDestination = "server"),
              ),
              const SizedBox(width: 10),
              _buildChoiceChip(
                selected: _selectedDestination == "client",
                label: "Download to Phone",
                icon: Icons.phone_android,
                accent: AppTheme.emeraldAccent,
                onTap: () => setState(() => _selectedDestination = "client"),
              ),
            ],
          ),
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
                        : (_selectedDestination == "client" ? "Download to Phone" : "Start Server Download"),
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
                    final isFinished = status == "finished" || status == "completed";
                    final isError = status == "error" || status == "failed";
                    final isPaused = status == "paused";
                    final isActive = !isFinished && !isError && !isPaused;
                    final isSaving = _savingTaskIds.contains(taskId);
                    final isSaved = _savedTaskIds.contains(taskId);

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
                              if (isPaused)
                                IconButton(
                                  tooltip: "Resume download",
                                  icon: const Icon(Icons.play_arrow, size: 18, color: AppTheme.emeraldAccent),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _resumeTask(taskId),
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
