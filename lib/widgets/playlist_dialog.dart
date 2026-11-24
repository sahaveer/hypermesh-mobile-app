import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

class PlaylistDialog extends StatefulWidget {
  final String songId;
  final String songTitle;

  const PlaylistDialog({super.key, required this.songId, required this.songTitle});

  @override
  State<PlaylistDialog> createState() => _PlaylistDialogState();
}

class _PlaylistDialogState extends State<PlaylistDialog> {
  final TextEditingController _newPlaylistController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hypermesh = context.watch<HypermeshProvider>();
    final playlists = hypermesh.playlists;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ADD TO PLAYLIST",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.songTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isCreating) ...[
              TextField(
                controller: _newPlaylistController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Playlist Name (e.g. Chill, Workout)",
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isCreating = false),
                    child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () async {
                      final name = _newPlaylistController.text.trim();
                      if (name.isNotEmpty) {
                        await hypermesh.createPlaylist(name);
                        final newPl = hypermesh.playlists.last;
                        await hypermesh.addSongToPlaylist(newPl.id, widget.songId);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Added to playlist '$name'!"), backgroundColor: AppTheme.cyanAccent),
                          );
                        }
                      }
                    },
                    child: const Text("Create & Add"),
                  ),
                ],
              ),
            ] else ...[
              // Create New Button
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0x3300E5FF),
                  child: Icon(Icons.add, color: AppTheme.cyanAccent),
                ),
                title: const Text("Create New Playlist", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.cyanAccent)),
                onTap: () => setState(() => _isCreating = true),
              ),
              const Divider(color: AppTheme.border),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text("No custom playlists yet.", style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      final alreadyIn = pl.songIds.contains(widget.songId);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.queue_music, color: AppTheme.textSecondary),
                        title: Text(pl.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        subtitle: Text("${pl.songIds.length} tracks", style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        trailing: alreadyIn
                            ? const Icon(Icons.check, color: AppTheme.emeraldAccent, size: 18)
                            : const Icon(Icons.add, color: AppTheme.textSecondary, size: 18),
                        onTap: alreadyIn
                            ? null
                            : () async {
                                await hypermesh.addSongToPlaylist(pl.id, widget.songId);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Added to '${pl.name}'"), backgroundColor: AppTheme.cyanAccent),
                                  );
                                }
                              },
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
