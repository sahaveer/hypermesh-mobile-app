import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

class AppUpdateDialog extends StatefulWidget {
  final UpdateInfo update;

  const AppUpdateDialog({super.key, required this.update});

  static Future<void> show(BuildContext context, UpdateInfo update) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDialog(update: update),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = "Ready to download";
  bool _hasError = false;

  void _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _hasError = false;
      _statusText = "Connecting...";
    });

    final success = await AppUpdateService.downloadAndInstall(
      update: widget.update,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
            _statusText = "Downloading update: ${(p * 100).toInt()}%";
          });
        }
      },
    );

    if (mounted) {
      if (!success) {
        setState(() {
          _isDownloading = false;
          _hasError = true;
          _statusText = "Failed to download update. Please try again.";
        });
      } else {
        Navigator.pop(context); // Close dialog once Android installer launches
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = widget.update;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: update.isPeerUpdate
                      ? AppTheme.cyanAccent.withOpacity(0.2)
                      : AppTheme.purpleAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      update.isPeerUpdate ? Icons.bolt : Icons.cloud_download,
                      color: update.isPeerUpdate ? AppTheme.cyanAccent : AppTheme.purpleAccent,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      update.isPeerUpdate ? "OFFLINE MESH UPDATE" : "SERVER OTA UPDATE",
                      style: TextStyle(
                        color: update.isPeerUpdate ? AppTheme.cyanAccent : AppTheme.purpleAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Hypermesh v${update.version} Available",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "From: ${update.sourceName}",
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Release notes box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "What's New:",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  update.releaseNotes,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (update.isPeerUpdate)
            const Row(
              children: [
                Icon(Icons.wifi, color: AppTheme.emeraldAccent, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Transfers over local Wi-Fi with 0 MB internet data.",
                    style: TextStyle(color: AppTheme.emeraldAccent, fontSize: 11),
                  ),
                ),
              ],
            ),

          if (_isDownloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: AppTheme.surfaceLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  update.isPeerUpdate ? AppTheme.cyanAccent : AppTheme.purpleAccent,
                ),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],

          if (_hasError) ...[
            const SizedBox(height: 12),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later", style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: update.isPeerUpdate ? AppTheme.cyanAccent : AppTheme.purpleAccent,
              foregroundColor: update.isPeerUpdate ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text("Install Update", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _startUpdate,
          ),
        ],
      ],
    );
  }
}
