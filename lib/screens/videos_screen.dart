import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_item.dart';
import '../providers/hypermesh_provider.dart';
import '../services/extension_patch_service.dart';
import '../widgets/server_downloader_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/download_destination_sheet.dart';
import '../widgets/admin_delete_dialog.dart';
import 'video_player_screen.dart';

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  void _showVideoActionMenu(BuildContext context, VideoItem video) {
    final hypermesh = context.read<HypermeshProvider>();
    final isFav = hypermesh.isFavorite(video.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_circle_outline, color: AppTheme.cyanAccent),
                title: const Text("Play Video", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(
                        video: video,
                        hostUrl: hypermesh.apiService.hostUrl,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: Colors.redAccent),
                title: Text(isFav ? "Remove from Favorites" : "Add to Favorites", style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  hypermesh.toggleFavorite(video.id);
                },
              ),
              if (!hypermesh.isLocalSharedMedia(video.id))
                ListTile(
                  leading: const Icon(Icons.download, color: AppTheme.emeraldAccent),
                  title: const Text("Download Options", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("Save a copy for offline playback", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    DownloadDestinationSheet.show(context, video);
                  },
                ),
              const Divider(color: AppTheme.border),

              // Option 1: If it's a locally shared video from this phone
              if (hypermesh.isLocalSharedMedia(video.id))
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, color: Colors.orangeAccent),
                  title: const Text(
                    "Stop Sharing / Remove from My Phone",
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Unshares this video from your phone (keeps original file on phone)",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    hypermesh.removeSharedFile(video.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Unshared '${video.title}' from your phone."),
                        backgroundColor: Colors.orangeAccent,
                      ),
                    );
                  },
                ),

              // Option 2: Remove from my list (hide unwanted peer or server video)
              if (!hypermesh.isLocalSharedMedia(video.id))
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined, color: Colors.orangeAccent),
                  title: const Text(
                    "Remove from My List (Hide)",
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Hides this video from your library so you don't see it again",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    hypermesh.removeVideoForMe(video.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Removed '${video.title}' for you."), backgroundColor: Colors.orangeAccent),
                    );
                  },
                ),

              // Option 3: Admin delete permanently from server
              if (!hypermesh.isLocalSharedMedia(video.id) && !video.isPeer && !video.id.startsWith("vid-demo-")) ...[
                const Divider(color: AppTheme.border),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text(
                    "DELETE FROM SERVER (ADMIN)",
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Permanently deletes video from the server for all users on the network",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    AdminDeleteDialog.show(
                      context,
                      mediaId: video.id,
                      title: video.title,
                      isVideo: true,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hypermesh = context.watch<HypermeshProvider>();
    final patchService = context.watch<ExtensionPatchService>();
    final videos = hypermesh.filteredVideos;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.movie, color: AppTheme.cyanAccent, size: 24),
                    SizedBox(width: 10),
                    Text(
                      "VIDEOS & MOVIES",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (patchService.isPatchActive || hypermesh.serverDownloaderAvailable) ...[
                      IconButton(
                        icon: const Icon(Icons.cloud_download, color: AppTheme.cyanAccent, size: 22),
                        tooltip: "Web Media Importer",
                        onPressed: () => ServerDownloaderDialog.show(context),
                      ),
                      const SizedBox(width: 4),
                    ],
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyanAccent.withOpacity(0.15),
                        foregroundColor: AppTheme.cyanAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: AppTheme.cyanAccent, width: 1),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("Add Videos", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final added = await hypermesh.pickLocalFiles(isVideo: true);
                        if (context.mounted && added > 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Added $added video(s) to your library & mesh!"),
                              backgroundColor: AppTheme.emeraldAccent,
                            ),
                          );
                          if (context.mounted) {
                            await hypermesh.checkAndPromptBackgroundSharing(context);
                          }
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        "${hypermesh.totalHypermeshVideosCount} Available",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.cyanAccent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _VideoFilterChip(
                  label: "All (${hypermesh.totalHypermeshVideosCount})",
                  isSelected: hypermesh.filter == MeshFilter.all,
                  selectedColor: AppTheme.cyanAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.all),
                ),
                const SizedBox(width: 8),
                _VideoFilterChip(
                  label: "On Device (${hypermesh.totalLocalVideosCount})",
                  isSelected: hypermesh.filter == MeshFilter.mine,
                  selectedColor: AppTheme.cyanAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.mine),
                ),
                const SizedBox(width: 8),
                _VideoFilterChip(
                  label: "Mesh Peers (${hypermesh.totalPeerVideosCount})",
                  isSelected: hypermesh.filter == MeshFilter.peers,
                  selectedColor: AppTheme.purpleAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.peers),
                ),
                const SizedBox(width: 8),
                _VideoFilterChip(
                  label: "Favorites ❤️",
                  isSelected: hypermesh.filter == MeshFilter.favorites,
                  selectedColor: Colors.redAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.favorites),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Videos Grid
          Expanded(
            child: hypermesh.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanAccent))
                : videos.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceLight,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: const Icon(Icons.movie, size: 36, color: AppTheme.cyanAccent),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No Videos in Library",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Add videos from your phone storage to watch offline with gesture controls or stream from peers.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary.withOpacity(0.9),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.cyanAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.folder_open, size: 20),
                                label: const Text("Select Videos from Device", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                onPressed: () => hypermesh.pickLocalFiles(isVideo: true),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => hypermesh.refreshLibrary(),
                        color: AppTheme.cyanAccent,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: videos.length,
                          itemBuilder: (context, index) {
                            final video = videos[index];
                            final isFav = hypermesh.isFavorite(video.id);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VideoPlayerScreen(
                                        video: video,
                                        hostUrl: hypermesh.apiService.hostUrl,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Video Thumbnail Box
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: 100,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(10),
                                              gradient: LinearGradient(
                                                colors: video.isPeer
                                                    ? [AppTheme.purpleAccent.withOpacity(0.7), const Color(0xFF1E0A3C)]
                                                    : [AppTheme.cyanAccent.withOpacity(0.7), const Color(0xFF00363A)],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: Center(
                                              child: Icon(
                                                video.isPeer ? Icons.live_tv : Icons.movie,
                                                color: Colors.white,
                                                size: 28,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.black.withOpacity(0.5),
                                            ),
                                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 14),

                                      // Video Info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              video.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: (video.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    video.resolution,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: video.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  video.formattedDuration,
                                                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                                ),
                                                if (video.formattedFilesize.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    "• ${video.formattedFilesize}",
                                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Source: ${video.sourceNodeName}",
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: video.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Actions
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isFav)
                                            const Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                                          if (video.isPeer)
                                            IconButton(
                                              tooltip: 'Pin to this device',
                                              icon: const Icon(Icons.push_pin_outlined, size: 18),
                                              onPressed: () => DownloadDestinationSheet.pin(context, video),
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
                                            onPressed: () => _showVideoActionMenu(context, video),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _VideoFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _VideoFilterChip({
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor.withOpacity(0.18) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? selectedColor : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? selectedColor : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
