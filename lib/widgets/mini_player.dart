import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import 'now_playing_sheet.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    if (song == null) {
      return const SizedBox.shrink();
    }

    final double progressRatio = player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => NowPlayingSheet(song: song),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent).withOpacity(0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Micro Progress Line
              LinearProgressIndicator(
                value: progressRatio,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Mini artwork
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          colors: song.isPeer
                              ? [AppTheme.purpleAccent, const Color(0xFF311B92)]
                              : [AppTheme.cyanAccent, const Color(0xFF006064)],
                        ),
                      ),
                      child: Icon(
                        song.isPeer ? Icons.cell_tower : Icons.music_note,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title and Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                song.isPeer ? "[⚡ ${song.sourceNodeName}] " : "[🏠 My Hub] ",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: song.isPeer ? AppTheme.purpleAccent : AppTheme.cyanAccent,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  player.loadFailed ? 'Playback failed. Tap play to retry.' : song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Play/Pause button
                    IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: AppTheme.textPrimary,
                        size: 28,
                      ),
                      onPressed: () => player.togglePlayPause(),
                    ),
                    // Next button
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: AppTheme.textSecondary,
                        size: 24,
                      ),
                      onPressed: () => player.next(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
