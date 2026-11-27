import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/peer_node.dart';
import 'background_mesh_service.dart';

class UpdateInfo {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;
  final bool isPeerUpdate;
  final String sourceName;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.isPeerUpdate,
    required this.sourceName,
  });

  bool get hasUpdate => buildNumber > AppConfig.buildNumber;
}

class AppUpdateService {
  static const String peerUpdatesEnabledKey = 'allow_peer_app_updates';

  /// Peer app updates are OFF by default: the UDP beacon's build_number
  /// is attacker-controllable on any LAN, so auto-trusting the highest
  /// build means auto-installing attacker-supplied APKs. A paired peer
  /// can also lie. The user must opt in in Settings before this fires.
  static Future<bool> peerUpdatesAllowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(peerUpdatesEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setPeerUpdatesAllowed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(peerUpdatesEnabledKey, value);
  }

  /// Checks for peer updates on local Wi-Fi / Hotspot (Option C - P2P Mesh Update).
  /// Returns null unless the caller explicitly opts in via [allowPeerUpdates];
  /// pair this with [peerUpdatesAllowed] on the call site.
  static UpdateInfo? checkPeerUpdates(
    List<PeerNode> peers, {
    bool allowPeerUpdates = false,
  }) {
    if (!allowPeerUpdates) return null;

    PeerNode? bestPeer;
    for (final peer in peers) {
      // Only paired peers (ones whose mesh token we already hold) are eligible.
      // An unpaired beacon on the LAN cannot push an install prompt.
      if (!peer.isOnline) continue;
      if (peer.meshToken == null || peer.meshToken!.isEmpty) continue;
      if (peer.buildNumber <= AppConfig.buildNumber) continue;
      if (bestPeer == null || peer.buildNumber > bestPeer.buildNumber) {
        bestPeer = peer;
      }
    }

    if (bestPeer != null) {
      final token = bestPeer.meshToken!;
      return UpdateInfo(
        version: bestPeer.appVersion,
        buildNumber: bestPeer.buildNumber,
        apkUrl: "${bestPeer.baseUrl}/api/app/latest.apk?t=${Uri.encodeQueryComponent(token)}",
        releaseNotes: "New update available from ${bestPeer.name} over local Wi-Fi mesh.",
        isPeerUpdate: true,
        sourceName: bestPeer.name,
      );
    }

    return null;
  }

  /// Checks for remote server updates (Option B - Online OTA Update)
  static Future<UpdateInfo?> checkServerUpdate(String hostUrl) async {
    try {
      final cleanHost = hostUrl.endsWith('/') ? hostUrl.substring(0, hostUrl.length - 1) : hostUrl;
      final uri = Uri.parse("$cleanHost/api/app/version");
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final buildNumber = (data['build_number'] is num) ? (data['build_number'] as num).toInt() : 1;
        final version = data['version']?.toString() ?? '1.0.0';
        var apkUrl = data['apk_url']?.toString() ?? '/api/app/latest.apk';

        if (apkUrl.startsWith('/')) {
          apkUrl = "$cleanHost$apkUrl";
        }

        final notes = data['release_notes']?.toString() ?? "Update available from server.";

        if (buildNumber > AppConfig.buildNumber) {
          return UpdateInfo(
            version: version,
            buildNumber: buildNumber,
            apkUrl: apkUrl,
            releaseNotes: notes,
            isPeerUpdate: false,
            sourceName: "Media Server",
          );
        }
      }
    } catch (_) {}

    return null;
  }

  /// Downloads the APK and triggers the native Android installer
  static Future<bool> downloadAndInstall({
    required UpdateInfo update,
    required Function(double progress) onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final updatesDir = Directory("${dir.path}/updates");
      if (!updatesDir.existsSync()) {
        await updatesDir.create(recursive: true);
      }

      final targetPath = "${updatesDir.path}/hypermesh-v${update.buildNumber}.apk";
      final targetFile = File(targetPath);

      // Download file with live progress
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200 && response.statusCode != 206) {
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final sink = targetFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress((downloaded / contentLength).clamp(0.0, 1.0));
        }
      }

      await sink.flush();
      await sink.close();

      onProgress(1.0);

      // Trigger Android system package installer
      final installed = await BackgroundMeshService.installApk(targetPath);
      return installed;
    } catch (e) {
      debugPrint("Error downloading/installing update: $e");
      return false;
    }
  }
}
