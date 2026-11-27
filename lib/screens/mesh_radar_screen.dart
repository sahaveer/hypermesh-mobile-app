import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/background_sharing_dialog.dart';
import '../widgets/app_update_dialog.dart';
import 'qr_peer_scanner_screen.dart';

class MeshRadarScreen extends StatelessWidget {
  const MeshRadarScreen({super.key});

  void _showMyQrSheet(BuildContext context, HypermeshProvider hypermesh) {
    final shareUrl = hypermesh.localShareUrl;
    // QR carries the paired shared secret (host+port+token) so the scanning
    // device can authenticate to this device's mesh server. The visible URL
    // below is just a human-readable address — the token stays in the QR.
    final qrPayload = hypermesh.localPairingPayload;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "${hypermesh.deviceName} • Share QR",
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "Friends on the same Wi-Fi or Hotspot can scan this QR from their Hypermesh app to stream your songs & videos.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link, color: AppTheme.cyanAccent, size: 18),
                    const SizedBox(width: 8),
                    SelectableText(
                      shareUrl,
                      style: const TextStyle(color: AppTheme.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: shareUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Copied $shareUrl"), backgroundColor: AppTheme.cyanAccent),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Sharing ${hypermesh.totalLocalCount} songs & ${hypermesh.totalLocalVideosCount} videos",
                style: const TextStyle(color: AppTheme.emeraldAccent, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditNodeNameDialog(BuildContext context, HypermeshProvider hypermesh) {
    final controller = TextEditingController(text: hypermesh.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text("Edit Node / Crew Name", style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This name will be broadcast to all peers on the Wi-Fi or Hotspot.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: "e.g. Captain Alex, Cabin 14",
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.cyanAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                hypermesh.updateDeviceName(controller.text.trim());
              }
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hypermesh = context.watch<HypermeshProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.cell_tower, color: AppTheme.cyanAccent, size: 22),
            SizedBox(width: 10),
            Text(
              "HYPERMESH RADAR",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: "Scan Local Mesh",
            onPressed: () => hypermesh.refreshLibrary(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => hypermesh.refreshLibrary(),
        color: AppTheme.cyanAccent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Update Banner (Option B or C)
            if (hypermesh.availableUpdate != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: hypermesh.availableUpdate!.isPeerUpdate
                        ? [AppTheme.cyanAccent.withOpacity(0.2), AppTheme.emeraldAccent.withOpacity(0.2)]
                        : [AppTheme.purpleAccent.withOpacity(0.2), AppTheme.cyanAccent.withOpacity(0.2)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hypermesh.availableUpdate!.isPeerUpdate ? AppTheme.cyanAccent : AppTheme.purpleAccent,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hypermesh.availableUpdate!.isPeerUpdate ? Icons.bolt : Icons.system_update_alt,
                        color: hypermesh.availableUpdate!.isPeerUpdate ? AppTheme.cyanAccent : AppTheme.purpleAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hypermesh.availableUpdate!.isPeerUpdate
                                ? "⚡ Offline Mesh Update Available!"
                                : "🚀 Server Update Available!",
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "v${hypermesh.availableUpdate!.version} from ${hypermesh.availableUpdate!.sourceName}",
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hypermesh.availableUpdate!.isPeerUpdate
                            ? AppTheme.cyanAccent
                            : AppTheme.purpleAccent,
                        foregroundColor: hypermesh.availableUpdate!.isPeerUpdate ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text("Update", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => AppUpdateDialog.show(context, hypermesh.availableUpdate!),
                    ),
                  ],
                ),
              ),

            // Top Swarm Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.cyanAccent.withOpacity(0.15),
                    AppTheme.purpleAccent.withOpacity(0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "FEDERATED SWARM POOL",
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.wifi, color: AppTheme.emeraldAccent, size: 16),
                          SizedBox(width: 6),
                          Text(
                            "0 MB Internet Used",
                            style: TextStyle(
                              color: AppTheme.emeraldAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        "${hypermesh.totalHypermeshCount + hypermesh.totalHypermeshVideosCount}",
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Media Files Shared",
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatChip(
                        label: "Songs in Swarm",
                        count: "${hypermesh.totalHypermeshCount} songs",
                        color: AppTheme.cyanAccent,
                        icon: Icons.music_note,
                      ),
                      const SizedBox(width: 12),
                      _StatChip(
                        label: "Movies in Swarm",
                        count: "${hypermesh.totalHypermeshVideosCount} videos",
                        color: AppTheme.purpleAccent,
                        icon: Icons.movie,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              "CONNECTED NODES ON WI-FI / HOTSPOT",
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),

            // Local Mobile Node Card
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showEditNodeNameDialog(context, hypermesh),
              child: _NodeCard(
                title: "${hypermesh.deviceName} (This Phone)",
                subtitle: "http://${hypermesh.localNodeIp}:${hypermesh.localNodePort} • Tap to rename",
                badge: hypermesh.isServerRunning ? "ACTIVE SEEDER" : "STARTING",
                badgeColor: AppTheme.cyanAccent,
                icon: Icons.smartphone,
                songsCount: hypermesh.totalLocalCount,
                videosCount: hypermesh.totalLocalVideosCount,
                isHost: true,
              ),
            ),
            const SizedBox(height: 12),

            // QR Connect & Share Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showMyQrSheet(context, hypermesh),
                    icon: const Icon(Icons.qr_code_2, size: 20),
                    label: const Text("Show My QR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.purpleAccent,
                      side: const BorderSide(color: AppTheme.purpleAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const QrPeerScannerScreen()),
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    label: const Text("Scan Peer QR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Background Keep-Alive Sharing Toggle Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hypermesh.isBackgroundServiceEnabled
                      ? AppTheme.cyanAccent.withOpacity(0.5)
                      : AppTheme.border,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: hypermesh.isBackgroundServiceEnabled
                          ? AppTheme.cyanAccent.withOpacity(0.15)
                          : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.bolt,
                      color: hypermesh.isBackgroundServiceEnabled
                          ? AppTheme.cyanAccent
                          : AppTheme.textSecondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Keep Node Active in Background",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hypermesh.isBackgroundServiceEnabled
                              ? "Active • Notification shown when locked"
                              : "Pauses when screen turns off",
                          style: TextStyle(
                            fontSize: 11,
                            color: hypermesh.isBackgroundServiceEnabled
                                ? AppTheme.emeraldAccent
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: hypermesh.isBackgroundServiceEnabled,
                    activeColor: AppTheme.cyanAccent,
                    onChanged: (val) async {
                      if (val) {
                        final ok = await BackgroundSharingDialog.show(context);
                        if (ok) {
                          await hypermesh.setBackgroundServiceEnabled(true);
                        }
                      } else {
                        await hypermesh.setBackgroundServiceEnabled(false);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Peer Node Cards
            if (hypermesh.peerNodes.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.wifi_tethering, size: 36, color: AppTheme.textSecondary),
                      SizedBox(height: 12),
                      Text(
                        "Broadcasting UDP beacon on Wi-Fi / Hotspot...",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Other phones running Hypermesh will appear here automatically.",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...hypermesh.peerNodes.map((peer) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _NodeCard(
                      title: peer.name,
                      subtitle: "${peer.host}:${peer.port} • Direct P2P Stream",
                      badge: "PEER NODE",
                      badgeColor: AppTheme.purpleAccent,
                      icon: Icons.cell_tower,
                      songsCount: peer.musicCount,
                      videosCount: peer.videoCount,
                      isHost: false,
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String count;
  final Color color;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                ),
                Text(
                  count,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final int songsCount;
  final int videosCount;
  final bool isHost;

  const _NodeCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.songsCount,
    this.videosCount = 0,
    required this.isHost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: badgeColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: badgeColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$songsCount 🎵",
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                "$videosCount 🎬",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
