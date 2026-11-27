import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../providers/player_provider.dart';
import '../services/background_mesh_service.dart';
import '../services/extension_patch_service.dart';
import '../widgets/server_downloader_dialog.dart';
import '../widgets/local_folders_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import 'videos_screen.dart';
import 'photos_screen.dart';
import 'mesh_radar_screen.dart';
import 'hub_connect_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isSelectionMode = false;
  final Set<String> _selectedSongIds = {};

  @override
  void initState() {
    super.initState();
    _initShareReceiver();
  }

  Future<void> _initShareReceiver() async {
    BackgroundMeshService.listenForSharedText(_handleIncomingSharedText);
    final initial = await BackgroundMeshService.getInitialSharedText();
    if (initial != null && initial.trim().isNotEmpty && mounted) {
      _handleIncomingSharedText(initial);
    }
  }

  void _handleIncomingSharedText(String sharedText) {
    if (!mounted) return;
    final match = RegExp(r'https?://\S+', caseSensitive: false).firstMatch(sharedText);
    final candidate = match?.group(0) ?? sharedText.trim();
    if (candidate.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ServerDownloaderDialog.show(context, initialUrl: candidate);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Current Tab Body
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildMusicTab(),
              const VideosScreen(),
              const PhotosScreen(),
              const MeshRadarScreen(),
              const HubConnectScreen(),
            ],
          ),

          // Docked MiniPlayer above Bottom Navigation
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note),
            label: "Music",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.movie_outlined),
            activeIcon: Icon(Icons.movie),
            label: "Videos",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library_outlined),
            activeIcon: Icon(Icons.photo_library),
            label: "Photos",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cell_tower),
            label: "Mesh Radar",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }

  Widget _buildMusicTab() {
    final hypermesh = context.watch<HypermeshProvider>();
    final player = context.watch<PlayerProvider>();
    final patchService = context.watch<ExtensionPatchService>();
    final songs = hypermesh.filteredSongs;
    final hasSearchQuery = hypermesh.searchQuery.trim().isNotEmpty;

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
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppTheme.cyanAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppTheme.cyanAccent, blurRadius: 8, spreadRadius: 1),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          "HYPERMESH",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Top action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hypermesh.localSongs.isNotEmpty) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: _isSelectionMode ? "Cancel selection" : "Multi-select tracks to share",
                        icon: Icon(
                          _isSelectionMode ? Icons.close : Icons.checklist,
                          color: _isSelectionMode ? Colors.orangeAccent : AppTheme.cyanAccent,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _isSelectionMode = !_isSelectionMode;
                            if (!_isSelectionMode) _selectedSongIds.clear();
                          });
                        },
                      ),
                    ],
                    if (patchService.isPatchActive || hypermesh.serverDownloaderAvailable) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.cloud_download, color: AppTheme.cyanAccent, size: 20),
                        tooltip: "Web Media Importer",
                        onPressed: () => ServerDownloaderDialog.show(context),
                      ),
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
                      icon: const Icon(Icons.folder_open, size: 15),
                      label: const Text("Folders / Add", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () => LocalFoldersSheet.show(context, defaultVideo: false),
                    ),
                    const SizedBox(width: 6),
                    // Peer status pill
                    GestureDetector(
                      onTap: () => setState(() => _currentIndex = 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.wifi_tethering, size: 13, color: AppTheme.emeraldAccent),
                            const SizedBox(width: 4),
                            Text(
                              "${hypermesh.peerNodes.length} Peers",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.emeraldAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => hypermesh.setSearchQuery(val),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surface,
                hintText: "Search titles, artists, or nodes...",
                hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          hypermesh.setSearchQuery("");
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.cyanAccent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Hypermesh Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: "All (${hypermesh.totalHypermeshCount})",
                  isSelected: hypermesh.filter == MeshFilter.all,
                  selectedColor: AppTheme.cyanAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: "On Device (${hypermesh.totalLocalCount})",
                  isSelected: hypermesh.filter == MeshFilter.mine,
                  selectedColor: AppTheme.cyanAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.mine),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: "Mesh Peers (${hypermesh.totalPeerCount})",
                  isSelected: hypermesh.filter == MeshFilter.peers,
                  selectedColor: AppTheme.purpleAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.peers),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: "Favorites ❤️",
                  isSelected: hypermesh.filter == MeshFilter.favorites,
                  selectedColor: Colors.redAccent,
                  onTap: () => hypermesh.setFilter(MeshFilter.favorites),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (_isSelectionMode)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.6)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_selectedSongIds.length} selected",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectedSongIds.isEmpty
                        ? null
                        : () async {
                            await hypermesh.setFilesSharedWithMesh(_selectedSongIds, true);
                            if (mounted) {
                              setState(() {
                                _isSelectionMode = false;
                                _selectedSongIds.clear();
                              });
                              await hypermesh.checkAndPromptBackgroundSharing(context);
                            }
                          },
                    child: const Text("Share", style: TextStyle(color: AppTheme.emeraldAccent, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: _selectedSongIds.isEmpty
                        ? null
                        : () async {
                            await hypermesh.setFilesSharedWithMesh(_selectedSongIds, false);
                            if (mounted) {
                              setState(() {
                                _isSelectionMode = false;
                                _selectedSongIds.clear();
                              });
                            }
                          },
                    child: const Text("Private", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // Songs List
          Expanded(
            child: hypermesh.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.cyanAccent))
                : songs.isEmpty
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
                                child: const Icon(Icons.music_note, size: 36, color: AppTheme.cyanAccent),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                hasSearchQuery ? "No Matching Songs" : "No Songs in Library",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                hasSearchQuery
                                    ? "No available audio files match \"${hypermesh.searchQuery.trim()}\"."
                                    : "Add audio files from your phone storage to play offline or stream from mesh peers.",
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
                                icon: Icon(hasSearchQuery ? Icons.clear : Icons.folder_open, size: 20),
                                label: Text(
                                  hasSearchQuery ? "Clear Search" : "Select Music / Video Folders",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                onPressed: () {
                                  if (hasSearchQuery) {
                                    _searchController.clear();
                                    hypermesh.setSearchQuery("");
                                  } else {
                                    LocalFoldersSheet.show(context, defaultVideo: false);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => hypermesh.refreshLibrary(),
                        color: AppTheme.cyanAccent,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96), // Clearance for miniplayer
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final isCurrent = player.currentSong?.id == song.id;
                            final isLocal = hypermesh.isLocalSharedMedia(song.id);
                            final isSelected = _selectedSongIds.contains(song.id);

                            return SongTile(
                              song: song,
                              isCurrent: isCurrent,
                              isPlaying: player.isPlaying,
                              isSelectionMode: _isSelectionMode,
                              isSelected: isSelected,
                              onLongPress: isLocal
                                  ? () {
                                      setState(() {
                                        _isSelectionMode = true;
                                        _selectedSongIds.add(song.id);
                                      });
                                    }
                                  : null,
                              onTap: () {
                                if (_isSelectionMode) {
                                  if (!isLocal) return;
                                  setState(() {
                                    if (isSelected) {
                                      _selectedSongIds.remove(song.id);
                                      if (_selectedSongIds.isEmpty) _isSelectionMode = false;
                                    } else {
                                      _selectedSongIds.add(song.id);
                                    }
                                  });
                                  return;
                                }
                                player.playSong(song, songs);
                              },
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _FilterChip({
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
