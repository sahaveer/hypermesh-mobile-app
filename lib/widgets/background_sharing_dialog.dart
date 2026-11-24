import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BackgroundSharingDialog {
  /// Shows an explicit, informative dialog asking the user if they want to enable background sharing
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.border),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.cyanAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bolt, color: AppTheme.cyanAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Keep Node Active?",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "When you lock your phone or turn off your screen, Android normally suspends background servers to save battery.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, color: AppTheme.emeraldAccent, size: 16),
                      SizedBox(width: 8),
                      Text(
                        "Status Notification",
                        style: TextStyle(
                          color: AppTheme.emeraldAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "\"Hypermesh Active: Sharing 4 files with 3 crew members\"",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Allows crew members on the ship to keep streaming your shared movies without interruption.",
                    style: TextStyle(
                      color: AppTheme.textSecondary.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "You can turn this off at any time from the Mesh Radar or Settings tab.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Not Now",
              style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Enable Background Sharing",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
