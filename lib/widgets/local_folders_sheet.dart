import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

class LocalFoldersSheet extends StatefulWidget {
  final bool defaultVideo;

  const LocalFoldersSheet({super.key, this.defaultVideo = false});

  static Future<void> show(BuildContext context, {bool defaultVideo = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocalFoldersSheet(defaultVideo: defaultVideo),
    );
  }

  @override
  State<LocalFoldersSheet> createState() => _LocalFoldersSheetState();
}

class _LocalFoldersSheetState extends State<LocalFoldersSheet> {
  bool _isBusy = false;

  Future<void> _handleSelectFolder() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);

    final hypermesh = context.read<HypermeshProvider>();
    final result = await hypermesh.pickLocalFolder();
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (result.folderPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Folder added! Found ${result.addedCount} new audio/video file(s)."),
          backgroundColor: AppTheme.emeraldAccent,
        ),
      );
      await hypermesh.checkAndPromptBackgroundSharing(context);
    }
  }

  Future<void> _handleRescan() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final hypermesh = context.read<HypermeshProvider>();
    final added = await hypermesh.rescanLocalFolders();
    if (!mounted) return;
    setState(() => _isBusy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added > 0 ? "Rescanned folders: added $added new file(s)." : "All linked folders are up to date."),
        backgroundColor: AppTheme.cyanAccent,
      ),
    );
  }

  Future<void> _handlePickFiles({required bool isVideo}) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final hypermesh = context.read<HypermeshProvider>();
    final added = await hypermesh.pickLocalFiles(isVideo: isVideo);
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (added > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Added $added ${isVideo ? 'video' : 'audio'} file(s) to your library & mesh!"),
          backgroundColor: AppTheme.emeraldAccent,
        ),
      );
      await hypermesh.checkAndPromptBackgroundSharing(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hypermesh = context.watch<HypermeshProvider>();
    final folders = hypermesh.sharedFolders;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.folder_copy, color: AppTheme.cyanAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Local Media Folders",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (_isBusy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Select one or multiple folders containing your audio & video files. Hypermesh plays them offline and shares them with connected mesh peers.",
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
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
                      onPressed: _isBusy ? null : _handleSelectFolder,
                      icon: const Icon(Icons.create_new_folder, size: 18),
                      label: const Text("Select Folder", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (folders.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.cyanAccent,
                        side: const BorderSide(color: AppTheme.cyanAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isBusy ? null : _handleRescan,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text("Rescan"),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (folders.isNotEmpty) ...[
                Text(
                  "LINKED FOLDERS (${folders.length})",
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: folders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final count = hypermesh.localMediaStore.countFilesInFolder(folder);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder, color: AppTheme.cyanAccent, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    folder,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    "$count audio/video file(s)",
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.orangeAccent, size: 20),
                              tooltip: "Remove folder",
                              onPressed: _isBusy ? null : () => hypermesh.removeLocalFolder(folder),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Divider(color: AppTheme.border),
              const SizedBox(height: 8),
              const Text(
                "OR PICK INDIVIDUAL FILES",
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isBusy ? null : () => _handlePickFiles(isVideo: false),
                      icon: const Icon(Icons.audiotrack, size: 18, color: AppTheme.cyanAccent),
                      label: const Text("Audio Files", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isBusy ? null : () => _handlePickFiles(isVideo: true),
                      icon: const Icon(Icons.video_library, size: 18, color: AppTheme.purpleAccent),
                      label: const Text("Video Files", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
