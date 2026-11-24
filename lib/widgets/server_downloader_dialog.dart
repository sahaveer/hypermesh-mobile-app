import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

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
  String? _statusFeedback;
  bool _feedbackIsError = false;
  Timer? _pollingTimer;
  List<Map<String, dynamic>> _tasks = [];

  final Set<String> _knownCompletedIds = {};
  final Set<String> _requestedClientTaskIds = {};
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
      hypermesh.refreshLibrary();
    }
    for (final task in tasksToAutoSave) {
      _saveTaskToPhone(task);
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

  Future<void> _handleStartDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

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
      destination: _selectedDestination,
      clientId: hypermesh.deviceId,
      deviceName: hypermesh.deviceName,
    );

    if (!mounted) return;

    final ok = res['ok'] == true;
    final taskId = res['task_id']?.toString();
    if (ok && taskId != null && _selectedDestination == 'client') {
      _requestedClientTaskIds.add(taskId);
    }

    setState(() {
      _isSubmitting = false;
      if (ok) {
        _urlController.clear();
        _feedbackIsError = false;
        _statusFeedback = _selectedDestination == 'client'
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      setState(() {
        _urlController.text = data!.text!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
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
                      "yt-dlp personal server bridge",
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

          // URL / Search Input
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Paste YouTube, Spotify link or song name...",
              hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              filled: true,
              fillColor: AppTheme.surfaceLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.link, color: AppTheme.cyanAccent, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste, color: AppTheme.textSecondary, size: 20),
                tooltip: "Paste from Clipboard",
                onPressed: _pasteFromClipboard,
              ),
            ),
          ),
          const SizedBox(height: 12),

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
          const SizedBox(height: 14),

          // Start Download Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),

          if (_statusFeedback != null) ...[
            const SizedBox(height: 10),
            Text(
              _statusFeedback!,
              style: TextStyle(
                color: _feedbackIsError ? Colors.redAccent : AppTheme.emeraldAccent,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 6),

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

          // Tasks List
          Expanded(
            child: _tasks.isEmpty
                ? const Center(
                    child: Text(
                      "No active downloads on server.",
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (ctx, idx) {
                      final task = _tasks[idx];
                      final taskId = task['id']?.toString() ?? '';
                      final title = task['title'] as String? ?? task['url'] as String? ?? "Unknown Media";
                      final status = (task['status'] as String? ?? "pending").toLowerCase();
                      final progress = (task['progress'] as num?)?.toDouble() ?? 0.0;
                      final dest = (task['destination'] as String? ?? 'server').toLowerCase();
                      final errorMsg = (task['error'] as String?)?.trim();
                      final isFinished = status == "finished" || status == "completed";
                      final isError = status == "error" || status == "failed";
                      final isSaving = _savingTaskIds.contains(taskId);
                      final isSaved = _savedTaskIds.contains(taskId);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isError ? Colors.redAccent.withOpacity(0.5) : AppTheme.border),
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
                                          : Icons.downloading,
                                  color: isFinished
                                      ? AppTheme.emeraldAccent
                                      : isError
                                          ? Colors.redAccent
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
                                      : isFinished
                                          ? "100%"
                                          : "${progress.toInt()}%",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isError
                                        ? Colors.redAccent
                                        : isFinished
                                            ? AppTheme.emeraldAccent
                                            : AppTheme.cyanAccent,
                                  ),
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
                    },
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
