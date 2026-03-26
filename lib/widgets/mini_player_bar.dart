import 'package:flutter/material.dart';

import '../controllers/local_music_player_controller.dart';
import 'song_artwork.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final LocalMusicPlayerController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = controller.currentTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Dismissible(
          key: ValueKey('mini-player-${track.id}'),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => controller.stopPlayback(clearSelection: true),
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! < -300) {
                onOpen();
              }
            },
            child: Material(
              color: const Color(0xFF1E1A2E),
              elevation: 12,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SongArtwork(
                        bytes: controller.artworkBytes,
                        isLoading: controller.isArtworkLoading,
                        size: 56,
                        borderRadius: 16,
                        iconSize: 24,
                        backgroundColor: const Color(0xFF2D2050),
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: controller.togglePlayback,
                        icon: Icon(
                          controller.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                          size: 34,
                          color: Colors.white,
                        ),
                        tooltip: controller.isPlaying ? 'Pause' : 'Play',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
}
}
