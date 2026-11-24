import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../models/video_item.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

class DownloadDestinationSheet extends StatelessWidget {
  final String title;
  final String sourceNodeName;
  final VoidCallback onDownloadLocal;
  final VoidCallback? onSaveToServer;

  const DownloadDestinationSheet({
    super.key,
    required this.title,
    required this.sourceNodeName,
    required this.onDownloadLocal,
    this.onSaveToServer,
  });

  static Future<void> pin(BuildContext context, Object item) async {
    final hub = context.read<HypermeshProvider>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Pinning to this device…')),
    );
    final saved = await hub.pinPeerMedia(item);
    if (!messenger.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Pinned to this device' : 'Could not pin this media',
        ),
      ),
    );
  }

  static void show(BuildContext context, Object item) {
    final (title, source, shareId) = switch (item) {
      Song() => (item.title, item.sourceNodeName, item.shareId),
      VideoItem() => (item.title, item.sourceNodeName, item.shareId),
      _ => throw ArgumentError.value(item, 'item'),
    };
    final hub = context.read<HypermeshProvider>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadDestinationSheet(
        title: title,
        sourceNodeName: source,
        onDownloadLocal: () => pin(context, item),
        onSaveToServer:
            shareId == null || shareId.isEmpty || hub.apiService.isDemo
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final saved = await hub.saveToHub(shareId);
                if (!messenger.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      saved ? 'Saved to My Hub' : 'Could not save to My Hub',
                    ),
                  ),
                );
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "DOWNLOAD DESTINATION",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // Option 1: Download to this phone
            InkWell(
              onTap: () {
                Navigator.pop(context);
                onDownloadLocal();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(0x3300E5FF),
                      child: Icon(
                        Icons.phone_android,
                        color: AppTheme.cyanAccent,
                      ),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Download to Phone",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Saves directly to your mobile device storage for offline playback",
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (onSaveToServer != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  onSaveToServer!();
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0x337C4DFF),
                        child: Icon(Icons.dns, color: AppTheme.purpleAccent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Save to My Hub (Server)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Copies from $sourceNodeName to your server library",
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
