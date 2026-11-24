import 'download_destination_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';

class NowPlayingSheet extends StatelessWidget {
  final Song song;

  const NowPlayingSheet({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              // Drag Handle
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textPrimary, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    song.isPeer ? "HYPERMESH STREAM" : "LOCAL HUB",
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                      color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz, color: AppTheme.textPrimary),
                    onPressed: () {},
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // Large Glowing Artwork
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: song.isPeer
                        ? [AppTheme.purpleAccent.withOpacity(0.8), const Color(0xFF1A0A3A)]
                        : [AppTheme.cyanAccent.withOpacity(0.8), const Color(0xFF002930)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    song.isPeer ? Icons.cell_tower : Icons.music_note,
                    size: 96,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(flex: 2),

              // Title & Artist + Mesh Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.loadFailed ? 'Playback failed. Tap play to retry.' : song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pin / Replicate Button for Peer Songs
                  if (song.isPeer)
                    IconButton(
                      icon: const Icon(Icons.cloud_download, color: AppTheme.purpleAccent, size: 28),
                      tooltip: 'Pin to this device',
                      onPressed: () => DownloadDestinationSheet.pin(context, song),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Node Source Pill
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        song.isPeer ? Icons.bolt : Icons.storage,
                        size: 14,
                        color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Source: ${song.sourceNodeName}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Scrub Bar
              ProgressBar(
                progress: player.position,
                total: player.duration,
                onSeek: (duration) => player.seek(duration),
                baseBarColor: AppTheme.surfaceLight,
                progressBarColor: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                bufferedBarColor: AppTheme.border,
                thumbColor: Colors.white,
                thumbGlowColor: (song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.3),
                timeLabelTextStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),

              // Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: player.isShuffle ? AppTheme.cyanAccent : AppTheme.textSecondary,
                      size: 24,
                    ),
                    onPressed: () => player.toggleShuffle(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: AppTheme.textPrimary, size: 36),
                    onPressed: () => player.previous(),
                  ),
                  GestureDetector(
                    onTap: () => player.togglePlayPause(),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: song.isPeer
                              ? [AppTheme.purpleAccent, const Color(0xFF651FFF)]
                              : [AppTheme.cyanAccent, const Color(0xFF00B0FF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        player.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: AppTheme.textPrimary, size: 36),
                    onPressed: () => player.next(),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.repeat,
                      color: player.isRepeat ? AppTheme.cyanAccent : AppTheme.textSecondary,
                      size: 24,
                    ),
                    onPressed: () => player.toggleRepeat(),
                  ),
                ],
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
