enum PlaybackStatus { idle, loading, playing, paused, completed, error }

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.trackId,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.status,
    required this.outputRoute,
    required this.outputLabel,
  });

  factory PlaybackSnapshot.idle() {
    return const PlaybackSnapshot(
      trackId: null,
      isPlaying: false,
      positionMs: 0,
      durationMs: 0,
      status: PlaybackStatus.idle,
      outputRoute: 'speaker',
      outputLabel: 'Phone speaker',
    );
  }

  factory PlaybackSnapshot.fromMap(Map<dynamic, dynamic> map) {
    int intOf(String key) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final rawStatus = map['status'];
    final status = rawStatus is String
        ? playbackStatusFromString(rawStatus)
        : PlaybackStatus.idle;

    return PlaybackSnapshot(
      trackId: map['trackId'] as String?,
      isPlaying: map['isPlaying'] == true,
      positionMs: intOf('positionMs'),
      durationMs: intOf('durationMs'),
      status: status,
      outputRoute: map['outputRoute'] as String? ?? 'speaker',
      outputLabel: map['outputLabel'] as String? ?? 'Phone speaker',
    );
  }

  final String? trackId;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final PlaybackStatus status;
  final String outputRoute;
  final String outputLabel;

  PlaybackSnapshot copyWith({
    String? trackId,
    bool? isPlaying,
    int? positionMs,
    int? durationMs,
    PlaybackStatus? status,
    String? outputRoute,
    String? outputLabel,
  }) {
    return PlaybackSnapshot(
      trackId: trackId ?? this.trackId,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      status: status ?? this.status,
      outputRoute: outputRoute ?? this.outputRoute,
      outputLabel: outputLabel ?? this.outputLabel,
    );
  }
}

PlaybackStatus playbackStatusFromString(String value) {
  switch (value) {
    case 'loading':
      return PlaybackStatus.loading;
    case 'playing':
      return PlaybackStatus.playing;
    case 'paused':
      return PlaybackStatus.paused;
    case 'completed':
      return PlaybackStatus.completed;
    case 'error':
      return PlaybackStatus.error;
    default:
      return PlaybackStatus.idle;
  }
}
