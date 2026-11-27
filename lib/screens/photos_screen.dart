import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hypermesh_provider.dart';
import '../theme/app_theme.dart';

enum _PhotoSourceTab { device, hub }

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  _PhotoSourceTab _tab = _PhotoSourceTab.device;
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  bool _isUploading = false;
  int _uploadDone = 0;
  int _uploadTotal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<HypermeshProvider>().loadPhotos();
      }
    });
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
      if (_selectedPaths.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  Future<void> _uploadFiles(List<File> files) async {
    if (files.isEmpty || _isUploading) return;
    final hypermesh = context.read<HypermeshProvider>();
    if (hypermesh.apiService.isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Connect to your Hypermesh Hub in Settings before uploading."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadDone = 0;
      _uploadTotal = files.length;
    });

    final res = await hypermesh.uploadSelectedPhotos(
      files,
      onItemProgress: (done, total) {
        if (mounted) {
          setState(() {
            _uploadDone = done;
            _uploadTotal = total;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _isSelectionMode = false;
      _selectedPaths.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Upload complete: ${res.uploaded} added, ${res.deduplicated} duplicate(s) skipped"
          "${res.pending > 0 ? ', ${res.pending} pending approval' : ''}"
          "${res.failed > 0 ? ', ${res.failed} failed' : ''}.",
        ),
        backgroundColor: res.failed > 0 ? Colors.orangeAccent : AppTheme.emeraldAccent,
      ),
    );
  }

  Future<void> _pickAndUploadMultiPhotos() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (picked.isEmpty || !mounted) return;
    final files = picked
        .where((p) => p.path != null)
        .map((p) => File(p.path!))
        .where((f) => f.existsSync())
        .toList();
    if (files.isEmpty) return;
    await _uploadFiles(files);
  }

  void _openLocalPhotoViewer(File file) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyanAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _uploadFiles([file]);
                      },
                      icon: const Icon(Icons.cloud_upload, size: 16),
                      label: const Text("Upload to Server", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openHubPhotoViewer(String title, String rawUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: rawUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const CircularProgressIndicator(color: AppTheme.cyanAccent),
                  errorWidget: (_, _, _) => const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hypermesh = context.watch<HypermeshProvider>();
    final localPhotos = hypermesh.localGalleryPhotos;
    final hubPhotos = hypermesh.hubPhotos;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.photo_library, color: AppTheme.cyanAccent, size: 22),
                    SizedBox(width: 10),
                    Text(
                      "PHOTOS",
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
                    if (_tab == _PhotoSourceTab.device && localPhotos.isNotEmpty)
                      IconButton(
                        tooltip: _isSelectionMode ? "Cancel selection" : "Multi-select photos to upload",
                        icon: Icon(
                          _isSelectionMode ? Icons.close : Icons.checklist,
                          color: _isSelectionMode ? Colors.orangeAccent : AppTheme.cyanAccent,
                        ),
                        onPressed: () {
                          setState(() {
                            _isSelectionMode = !_isSelectionMode;
                            if (!_isSelectionMode) _selectedPaths.clear();
                          });
                        },
                      ),
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
                      onPressed: _isUploading ? null : _pickAndUploadMultiPhotos,
                      icon: const Icon(Icons.add_photo_alternate, size: 16),
                      label: const Text("Upload Photos", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter Chips (Private on Device vs On Hub)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _PhotoTabChip(
                  label: "On Device (${localPhotos.length})",
                  selected: _tab == _PhotoSourceTab.device,
                  color: AppTheme.cyanAccent,
                  onTap: () => setState(() => _tab = _PhotoSourceTab.device),
                ),
                const SizedBox(width: 8),
                _PhotoTabChip(
                  label: "On Hub (${hubPhotos.length})",
                  selected: _tab == _PhotoSourceTab.hub,
                  color: AppTheme.emeraldAccent,
                  onTap: () {
                    setState(() {
                      _tab = _PhotoSourceTab.hub;
                      _isSelectionMode = false;
                      _selectedPaths.clear();
                    });
                    hypermesh.loadPhotos();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          if (_isUploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Uploading $_uploadDone / $_uploadTotal photo(s) with SHA-256 deduplication...",
                    style: const TextStyle(color: AppTheme.cyanAccent, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _uploadTotal > 0 ? _uploadDone / _uploadTotal : null,
                    backgroundColor: AppTheme.surfaceLight,
                    color: AppTheme.emeraldAccent,
                  ),
                ],
              ),
            ),

          if (_isSelectionMode && _selectedPaths.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                      "${_selectedPaths.length} selected",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emeraldAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    onPressed: _isUploading
                        ? null
                        : () {
                            final chosen = localPhotos
                                .where((f) => _selectedPaths.contains(f.path))
                                .toList();
                            _uploadFiles(chosen);
                          },
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: const Text("Upload to Server", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          Expanded(
            child: _tab == _PhotoSourceTab.device
                ? _buildDeviceGrid(localPhotos, hypermesh)
                : _buildHubGrid(hubPhotos, hypermesh),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceGrid(List<File> localPhotos, HypermeshProvider hypermesh) {
    if (localPhotos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.photo_library_outlined, size: 48, color: AppTheme.cyanAccent),
              const SizedBox(height: 12),
              const Text(
                "No Local Photos Found",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                "Browse photos privately in the app, or tap Upload Photos to multi-select and back up photos explicitly to your Hub.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => hypermesh.loadPhotos(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text("Scan Device Photos", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => hypermesh.loadPhotos(),
      color: AppTheme.cyanAccent,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: localPhotos.length,
        itemBuilder: (context, index) {
          final file = localPhotos[index];
          final selected = _selectedPaths.contains(file.path);
          return GestureDetector(
            onTap: () {
              if (_isSelectionMode) {
                _toggleSelection(file.path);
              } else {
                _openLocalPhotoViewer(file);
              }
            },
            onLongPress: () {
              setState(() => _isSelectionMode = true);
              _toggleSelection(file.path);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 320,
                    errorBuilder: (_, _, _) => Container(
                      color: AppTheme.surfaceLight,
                      child: const Icon(Icons.broken_image, color: Colors.white38),
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: AppTheme.cyanAccent.withOpacity(0.28),
                      border: Border.all(color: AppTheme.cyanAccent, width: 2.5),
                    ),
                  ),
                if (_isSelectionMode)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? AppTheme.cyanAccent : Colors.white70,
                      size: 22,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHubGrid(List<Map<String, dynamic>> hubPhotos, HypermeshProvider hypermesh) {
    if (hubPhotos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 46, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(
                hypermesh.apiService.isDemo
                    ? "Connect to Your Hub in Settings"
                    : "No Photos on Hub Yet",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                "Tap Upload Photos or long-press local photos to upload them explicitly to your Hub.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => hypermesh.loadPhotos(),
      color: AppTheme.emeraldAccent,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: hubPhotos.length,
        itemBuilder: (context, index) {
          final photo = hubPhotos[index];
          final id = photo['id']?.toString() ?? '';
          final title = photo['title']?.toString() ?? 'Photo';
          final thumbUrl = hypermesh.apiService.getPhotoThumbUrl(id);
          final rawUrl = hypermesh.apiService.getPhotoRawUrl(id);
          return GestureDetector(
            onTap: () => _openHubPhotoViewer(title, rawUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: thumbUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppTheme.surfaceLight),
                errorWidget: (_, _, _) => Container(
                  color: AppTheme.surfaceLight,
                  child: const Icon(Icons.broken_image, color: Colors.white38),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PhotoTabChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppTheme.border, width: selected ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? color : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
