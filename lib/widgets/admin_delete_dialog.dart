import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

class AdminDeleteDialog {
  static Future<void> show(
    BuildContext context, {
    required String mediaId,
    required String title,
    required bool isVideo,
  }) async {
    final hypermesh = context.read<HypermeshProvider>();

    if (hypermesh.isAdmin) {
      // Already authenticated as admin, show direct confirmation
      _showConfirmationDialog(context, hypermesh, mediaId, title, isVideo);
    } else {
      // Need admin password
      _showPasswordDialog(context, hypermesh, mediaId, title, isVideo);
    }
  }

  static void _showPasswordDialog(
    BuildContext context,
    HypermeshProvider hypermesh,
    String mediaId,
    String title,
    bool isVideo,
  ) {
    final controller = TextEditingController();
    bool isSubmitting = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.redAccent),
          ),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.redAccent, size: 24),
              SizedBox(width: 10),
              Text(
                "Admin Access Required",
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "To permanently delete '$title' from the server for all users, please enter the server admin password.",
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  hintText: "Server Admin Password",
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textSecondary, size: 20),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final pass = controller.text.trim();
                      if (pass.isEmpty) return;

                      setState(() {
                        isSubmitting = true;
                        errorMessage = null;
                      });

                      final verified = await hypermesh.verifyAdminPassword(pass);
                      if (!verified) {
                        setState(() {
                          isSubmitting = false;
                          errorMessage = "Invalid admin password or server unreachable.";
                        });
                        return;
                      }

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (context.mounted) {
                        _showConfirmationDialog(context, hypermesh, mediaId, title, isVideo);
                      }
                    },
              child: Text(isSubmitting ? "Verifying..." : "Verify Password"),
            ),
          ],
        ),
      ),
    );
  }

  static void _showConfirmationDialog(
    BuildContext context,
    HypermeshProvider hypermesh,
    String mediaId,
    String title,
    bool isVideo,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.redAccent),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text(
              "Permanently Delete?",
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to permanently delete '$title' from the server?",
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "This action will permanently delete the physical file on the server. All network peers will no longer be able to stream or download it.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text("Delete from Server", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await hypermesh.deleteMediaPermanently(mediaId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? "Permanently deleted '$title' from server." : "Failed to delete from server."),
                    backgroundColor: ok ? Colors.redAccent : Colors.orangeAccent,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
