import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';

/// Displays an in-app summary of Hypermesh's privacy practices along with a
/// copyable link to the full public privacy policy document.
Future<void> showPrivacyPolicyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.border),
      ),
      title: const Row(
        children: [
          Icon(Icons.privacy_tip_outlined, color: AppTheme.cyanAccent, size: 22),
          SizedBox(width: 10),
          Text(
            "Privacy Policy",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Hypermesh is a local-first, self-hosted P2P media player with no third-party ads or tracking SDKs.\n\n"
              "• Local Storage: Your hub URLs, playlists, favorites, and optional sign-in state stay on your device.\n"
              "• Optional OTP Sign-In: Email is sent only to your configured Google Apps Script endpoint when you request a code.\n"
              "• Media & Camera: Local media access powers offline playback (mesh sharing stays off per file unless enabled). Camera is used only for QR peer pairing.\n\n"
              "Full policy:",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 8),
            SelectableText(
              AppConfig.privacyPolicyUrl,
              style: const TextStyle(
                color: AppTheme.cyanAccent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 15, color: AppTheme.cyanAccent),
          label: const Text("Copy URL", style: TextStyle(color: AppTheme.cyanAccent)),
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: AppConfig.privacyPolicyUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Privacy policy URL copied"),
                backgroundColor: AppTheme.cyanAccent,
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.cyanAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text("Close"),
        ),
      ],
    ),
  );
}
