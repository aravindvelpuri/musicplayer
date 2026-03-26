import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;

import '../controllers/local_music_player_controller.dart';
import '../models/music_file.dart';
import '../utils/formatters.dart';
import '../widgets/song_artwork.dart';
import '../widgets/track_meta_card.dart';

class NowPlayingPanel extends StatefulWidget {
  const NowPlayingPanel({
    super.key,
    required this.controller,
    required this.onMinimize,
  });

  final LocalMusicPlayerController controller;
  final VoidCallback onMinimize;

  @override
  State<NowPlayingPanel> createState() => _NowPlayingPanelState();
}

class _NowPlayingPanelState extends State<NowPlayingPanel> {
  double? _dragValueMs;

  Future<void> _showTrackDetails(BuildContext context, MusicFile track) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(child: TrackMetaCard(track: track)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null &&
            details.primaryVelocity! > 500) {
          widget.onMinimize();
        }
      },
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer,
                const Color(0xFFEDE0CC),
                theme.scaffoldBackgroundColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final track = widget.controller.currentTrack;
              if (track == null) {
                return Center(
                  child: Text(
                    'No track selected',
                    style: theme.textTheme.titleLarge,
                  ),
                );
              }

              final snapshot = widget.controller.snapshot;
              final totalDurationMs = math.max(
                snapshot.durationMs,
                track.durationMs,
              );
              final sliderMax = math.max(totalDurationMs.toDouble(), 1.0);
              final sliderValue =
                  ((_dragValueMs ?? snapshot.positionMs.toDouble()).clamp(
                    0.0,
                    sliderMax,
                  )).toDouble();
              final repeatMode = widget.controller.repeatMode;

    final screenSize = MediaQuery.of(context).size;
    final artworkSize = math.min(
      screenSize.width - 48,
      math.min(screenSize.height * 0.42, 460.0),
    );

                  return Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, bottomInset + 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 112,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _PlayerHeaderButton(
                                  icon: Icons.keyboard_arrow_down_rounded,
                                  tooltip: 'Minimize player',
                                  onPressed: widget.onMinimize,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    'Now Playing',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  Text(
                                    widget.controller.queueSummary,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 112,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _PlayerHeaderButton(
                                    icon: Icons.info_outline_rounded,
                                    tooltip: 'Track details',
                                    onPressed: () =>
                                        _showTrackDetails(context, track),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 4,
                                child: Center(
                                  child: Container(
                                    width: artworkSize,
                                    height: artworkSize,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.22,
                                      ),
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.36,
                                        ),
                                        width: 1.4,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.10,
                                          ),
                                          blurRadius: 28,
                                          offset: const Offset(0, 16),
                                        ),
                                      ],
                                    ),
                                    child: SongArtwork(
                                      bytes: widget.controller.artworkBytes,
                                      isLoading:
                                          widget.controller.isArtworkLoading,
                                      size: artworkSize,
                                      height: artworkSize,
                                      borderRadius: 28,
                                      iconSize: artworkSize * 0.28,
                                      backgroundColor: theme
                                          .colorScheme
                                          .secondaryContainer
                                          .withValues(alpha: 0.98),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                track.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                track.artist,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.album,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge,
                              ),
                              const Spacer(),
                              Center(
                                child: _OutputRouteChip(
                                  icon: _outputRouteIcon(
                                    widget.controller.outputRoute,
                                  ),
                                  label: widget.controller.outputLabel,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                ),
                                child: Slider(
                                  value: sliderValue,
                                  min: 0,
                                  max: sliderMax,
                                  onChanged: (value) {
                                    setState(() {
                                      _dragValueMs = value;
                                    });
                                  },
                                  onChangeEnd: (value) async {
                                    setState(() {
                                      _dragValueMs = null;
                                    });
                                    await widget.controller.seekTo(
                                      value.round(),
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      formatDuration(
                                        (_dragValueMs ??
                                                snapshot.positionMs.toDouble())
                                            .round(),
                                      ),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const Spacer(),
                                    Text(
                                      formatDuration(totalDurationMs),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _PlayerModeButton(
                                      icon: Icons.shuffle_rounded,
                                      tooltip:
                                          widget.controller.isShuffleEnabled
                                          ? 'Shuffle on'
                                          : 'Shuffle off',
                                      isActive:
                                          widget.controller.isShuffleEnabled,
                                      onPressed:
                                          widget.controller.toggleShuffle,
                                    ),
                                  ),
                                  Expanded(
                                    child: IconButton(
                                      onPressed: widget.controller.hasPrevious
                                          ? widget.controller.playPrevious
                                          : null,
                                      iconSize: 38,
                                      icon: const Icon(
                                        Icons.skip_previous_rounded,
                                      ),
                                      tooltip: 'Previous',
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: SizedBox.square(
                                        dimension: 92,
                                        child: FilledButton(
                                          onPressed:
                                              widget.controller.togglePlayback,
                                          style: FilledButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            shape: const CircleBorder(),
                                            backgroundColor:
                                                theme.colorScheme.primary,
                                            foregroundColor:
                                                theme.colorScheme.onPrimary,
                                          ),
                                          child: Icon(
                                            widget.controller.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: IconButton(
                                      onPressed: widget.controller.hasNext
                                          ? widget.controller.playNext
                                          : null,
                                      iconSize: 38,
                                      icon: const Icon(Icons.skip_next_rounded),
                                      tooltip: 'Next',
                                    ),
                                  ),
                                  Expanded(
                                    child: _PlayerModeButton(
                                      icon: repeatMode == RepeatMode.one
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                      tooltip: _repeatModeLabel(repeatMode),
                                      isActive: repeatMode != RepeatMode.off,
                                      onPressed:
                                          widget.controller.cycleRepeatMode,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
            },
          ),
        ),
      ),
    ),
  );
}
}

String _repeatModeLabel(RepeatMode mode) {
  return switch (mode) {
    RepeatMode.off => 'Repeat off',
    RepeatMode.all => 'Repeat all',
    RepeatMode.one => 'Repeat one',
  };
}

IconData _outputRouteIcon(String route) {
  return switch (route) {
    'bluetooth' => Icons.bluetooth_audio_rounded,
    'headphones' => Icons.headphones_rounded,
    'earpiece' => Icons.hearing_rounded,
    _ => Icons.volume_up_rounded,
  };
}

class _PlayerHeaderButton extends StatelessWidget {
  const _PlayerHeaderButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x26FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 26,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerModeButton extends StatelessWidget {
  const _PlayerModeButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        iconSize: 26,
        color: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        icon: Icon(icon),
      ),
    );
  }
}

class _OutputRouteChip extends StatelessWidget {
  const _OutputRouteChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
