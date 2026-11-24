import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';
import 'download_destination_sheet.dart';
import 'playlist_dialog.dart';
import 'admin_delete_dialog.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  const SongTile({
    super.key,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  void _showActionMenu(BuildContext context) {
    final hypermesh = context.read<HypermeshProvider>();
    final isFav = hypermesh.isFavorite(song.id);

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
                leading: const Icon(Icons.playlist_add, color: AppTheme.cyanAccent),
                title: const Text("Add to Playlist", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showDialog(
                    context: context,
                    builder: (_) => PlaylistDialog(songId: song.id, songTitle: song.title),
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: Colors.redAccent,
                ),
                title: Text(isFav ? "Remove from Favorites" : "Add to Favorites",
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  hypermesh.toggleFavorite(song.id);
                },
              ),
              if (!hypermesh.isLocalSharedMedia(song.id))
                ListTile(
                  leading: const Icon(Icons.download, color: AppTheme.emeraldAccent),
                  title: const Text("Download Options", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("Save a copy for offline playback", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    DownloadDestinationSheet.show(context, song);
                  },
                ),
              const Divider(color: AppTheme.border),

              // Option 1: If it's a locally shared file from this phone
              if (hypermesh.isLocalSharedMedia(song.id))
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline, color: Colors.orangeAccent),
                  title: const Text(
                    "Stop Sharing / Remove from My Phone",
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Unshares this song from your phone (keeps original file on phone)",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    hypermesh.removeSharedFile(song.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Unshared '${song.title}' from your phone."),
                        backgroundColor: Colors.orangeAccent,
                      ),
                    );
                  },
                ),

              // Option 2: Remove from my list (hide unwanted peer or server files)
              if (!hypermesh.isLocalSharedMedia(song.id))
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined, color: Colors.orangeAccent),
                  title: const Text(
                    "Remove from My List (Hide)",
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Hides this song from your view so you don't hear or see it again",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    hypermesh.removeSongForMe(song.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Removed '${song.title}' from your list."),
                        backgroundColor: Colors.orangeAccent,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),

              // Option 3: Admin delete permanently from server
              if (!hypermesh.isLocalSharedMedia(song.id) && !song.isPeer && !song.id.startsWith("demo-")) ...[
                const Divider(color: AppTheme.border),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text(
                    "DELETE FROM SERVER (ADMIN)",
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Permanently deletes file from the server for all users on the network",
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    AdminDeleteDialog.show(
                      context,
                      mediaId: song.id,
                      title: song.title,
                      isVideo: false,
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
    final isFav = hypermesh.isFavorite(song.id);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.surfaceLight : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? AppTheme.cyanAccent : AppTheme.border,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: song.isPeer
                      ? [AppTheme.purpleAccent, const Color(0xFF311B92)]
                      : [AppTheme.cyanAccent, const Color(0xFF006064)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                song.isPeer ? Icons.cell_tower : Icons.music_note,
                color: Colors.white,
                size: 24,
              ),
            ),
            if (isCurrent && isPlaying)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.equalizer, color: AppTheme.cyanAccent, size: 24),
              ),
          ],
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isCurrent ? AppTheme.cyanAccent : AppTheme.textPrimary,
          ),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    song.isPeer ? Icons.bolt : Icons.storage,
                    size: 11,
                    color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    song.sourceNodeName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isFav)
              const Icon(Icons.favorite, size: 16, color: Colors.redAccent)
            else
              Text(
                song.formattedDuration,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            const SizedBox(width: 4),
            if (song.isPeer)
              IconButton(
                tooltip: 'Pin to this device',
                icon: const Icon(Icons.push_pin_outlined, size: 18),
                onPressed: () => DownloadDestinationSheet.pin(context, song),
              ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textSecondary),
              onPressed: () => _showActionMenu(context),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
