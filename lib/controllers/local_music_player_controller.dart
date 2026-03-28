import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_file.dart';
import '../models/playback_snapshot.dart';
import '../services/device_music_service.dart';

class LocalMusicPlayerController extends ChangeNotifier {
  LocalMusicPlayerController(this._deviceMusicService) {
    _eventsSubscription = _deviceMusicService.playerEvents().listen(
      _handlePlaybackEvent,
      onError: (_) {},
    );
    _remoteCommandSubscription = _deviceMusicService.remoteCommands().listen(
      _handleRemoteCommand,
      onError: (_) {},
    );
  }

  static const String _prefKeyTrackId = 'last_track_id';
  static const String _prefKeyPosition = 'last_position_ms';

  Future<void> _savePlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final track = currentTrack;
    if (track != null) {
      await prefs.setString(_prefKeyTrackId, track.id);
      await prefs.setInt(_prefKeyPosition, _snapshot.positionMs);
    } else {
      await prefs.remove(_prefKeyTrackId);
      await prefs.remove(_prefKeyPosition);
    }
  }

  Future<void> restoreState(List<MusicFile> allFiles) async {
    final prefs = await SharedPreferences.getInstance();
    final trackId = prefs.getString(_prefKeyTrackId);
    final positionMs = prefs.getInt(_prefKeyPosition) ?? 0;

    if (trackId == null || allFiles.isEmpty) {
      return;
    }

    final index = allFiles.indexWhere((track) => track.id == trackId);
    if (index >= 0) {
      final track = allFiles[index];
      _currentIndex = index;
      _snapshot = PlaybackSnapshot(
        trackId: track.id,
        isPlaying: false,
        positionMs: positionMs,
        durationMs: track.durationMs,
        status: PlaybackStatus.paused,
        outputRoute: _snapshot.outputRoute,
        outputLabel: _snapshot.outputLabel,
      );
      _setArtworkForTrack(track);
      notifyListeners();

      // Ensure artwork is loaded
      unawaited(_loadArtwork(track));
    }
  }

  final DeviceMusicService _deviceMusicService;
  final Map<String, Uint8List?> _artworkCache = <String, Uint8List?>{};
  final Set<String> _artworkLoadingTrackIds = <String>{};
  final math.Random _random = math.Random();
  StreamSubscription<PlaybackSnapshot>? _eventsSubscription;
  StreamSubscription<String>? _remoteCommandSubscription;
  final StreamController<String> _uiCommandController = StreamController<String>.broadcast();

  Stream<String> get uiCommands => _uiCommandController.stream;

  List<MusicFile> get queue => _queue;

  PaletteGenerator? _currentPalette;
  PaletteGenerator? get currentPalette => _currentPalette;

  List<MusicFile> _queue = const <MusicFile>[];
  final List<int> _shuffleHistory = <int>[];
  int _currentIndex = -1;
  PlaybackSnapshot _snapshot = PlaybackSnapshot.idle();
  Uint8List? _artworkBytes;
  bool _isArtworkLoading = false;
  bool _isAutoAdvancing = false;
  bool _isShuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.off;

  MusicFile? get currentTrack {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      return null;
    }
    return _queue[_currentIndex];
  }

  PlaybackSnapshot get snapshot => _snapshot;
  Uint8List? get artworkBytes => _artworkBytes;
  bool get isArtworkLoading => _isArtworkLoading;
  bool get isPlaying => _snapshot.isPlaying;
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  String get outputRoute => _snapshot.outputRoute;
  String get outputLabel => _snapshot.outputLabel;

  Uint8List? artworkForTrack(MusicFile track) {
    if (currentTrack?.id == track.id) {
      return _artworkBytes ?? _artworkCache[track.id];
    }
    return _artworkCache[track.id];
  }

  bool isArtworkLoadingForTrack(MusicFile track) {
    if (currentTrack?.id == track.id) {
      return _isArtworkLoading;
    }
    return _artworkLoadingTrackIds.contains(track.id);
  }

  bool get hasNext {
    if (_currentIndex < 0 || _queue.isEmpty) {
      return false;
    }
    if (_isShuffleEnabled) {
      return _queue.length > 1;
    }
    if (_currentIndex < _queue.length - 1) {
      return true;
    }
    return _repeatMode == RepeatMode.all && _queue.length > 1;
  }

  bool get hasPrevious {
    if (_snapshot.positionMs > 3000) {
      return true;
    }
    if (_isShuffleEnabled && _shuffleHistory.isNotEmpty) {
      return true;
    }
    if (_currentIndex > 0) {
      return true;
    }
    return _repeatMode == RepeatMode.all && _queue.length > 1;
  }

  String get queueSummary {
    if (_queue.isEmpty || _currentIndex < 0) {
      return 'Offline music library';
    }
    return 'Track ${_currentIndex + 1} of ${_queue.length}';
  }

  String? _playbackContext;
  String? get playbackContext => _playbackContext;

  String? _currentPlaylistId;
  String? get currentPlaylistId => _currentPlaylistId;

  void setQueue(
    List<MusicFile> queue, {
    int initialIndex = -1,
    String? playbackContext,
    String? playlistId,
  }) {
    _queue = List<MusicFile>.unmodifiable(queue);
    _playbackContext = playbackContext;
    _currentPlaylistId = playlistId;
    _shuffleHistory.removeWhere((index) => index < 0 || index >= _queue.length);

    if (_queue.isEmpty) {
      _currentIndex = -1;
      _snapshot = PlaybackSnapshot.idle();
      _artworkBytes = null;
      _isArtworkLoading = false;
      _shuffleHistory.clear();
      notifyListeners();
      return;
    }

    if (initialIndex >= 0 && initialIndex < _queue.length) {
      _playTrackAt(initialIndex, recordHistory: false);
    } else {
      final trackId = _snapshot.trackId;
      if (trackId != null) {
        final updatedIndex = _queue.indexWhere((song) => song.id == trackId);
        if (updatedIndex >= 0) {
          _currentIndex = updatedIndex;
        } else {
          _currentIndex = -1;
          _snapshot = PlaybackSnapshot.idle();
          _artworkBytes = null;
          _isArtworkLoading = false;
        }
      } else if (_currentIndex >= _queue.length) {
        _currentIndex = -1;
      }
    }

    notifyListeners();
    _syncNativeQueue();
  }

  Future<void> playTrackAt(int index) async {
    await _playTrackAt(index);
  }

  Future<void> _playTrackAt(int index, {bool recordHistory = true}) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    if (recordHistory &&
        _currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        _currentIndex != index) {
      _shuffleHistory.add(_currentIndex);
    }

    final track = _queue[index];
    _currentIndex = index;
    _snapshot = PlaybackSnapshot(
      trackId: track.id,
      isPlaying: false,
      positionMs: 0,
      durationMs: track.durationMs,
      status: PlaybackStatus.loading,
      outputRoute: _snapshot.outputRoute,
      outputLabel: _snapshot.outputLabel,
    );
    _setArtworkForTrack(track);
    notifyListeners();

    await _deviceMusicService.playTrack(track);
    _syncNativeQueue();
    await _loadArtwork(track);
    _extractPalette(track);
    unawaited(_savePlaybackState());
  }

  Future<void> togglePlayback() async {
    if (currentTrack == null) {
      return;
    }

    if (_snapshot.isPlaying) {
      await _deviceMusicService.pausePlayback();
    } else {
      await _deviceMusicService.resumePlayback();
    }
    unawaited(_savePlaybackState());
  }

  Future<void> playNext() async {
    if (!hasNext) {
      return;
    }

    if (_isShuffleEnabled && _queue.length > 1) {
      await _playTrackAt(_randomNextIndex());
      return;
    }

    if (_currentIndex >= _queue.length - 1 && _repeatMode == RepeatMode.all) {
      await _playTrackAt(0);
      return;
    }

    await _playTrackAt(_currentIndex + 1);
  }

  Future<void> playPrevious() async {
    if (_snapshot.positionMs > 3000) {
      await seekTo(0);
      return;
    }

    if (_isShuffleEnabled && _shuffleHistory.isNotEmpty) {
      final previousIndex = _shuffleHistory.removeLast();
      await _playTrackAt(previousIndex, recordHistory: false);
      return;
    }

    if (_currentIndex <= 0) {
      if (_repeatMode == RepeatMode.all && _queue.length > 1) {
        await _playTrackAt(_queue.length - 1);
        return;
      }

      await seekTo(0);
      return;
    }

    await _playTrackAt(_currentIndex - 1);
  }

  Future<void> seekTo(int positionMs) async {
    _snapshot = _snapshot.copyWith(
      positionMs: positionMs,
      status: _snapshot.status == PlaybackStatus.completed
          ? PlaybackStatus.paused
          : null,
    );
    notifyListeners();
    await _deviceMusicService.seekTo(positionMs);
    unawaited(_savePlaybackState());
  }

  Future<void> stopPlayback({bool clearSelection = true}) async {
    await _deviceMusicService.stopPlayback();

    if (clearSelection) {
      _currentIndex = -1;
      _snapshot = PlaybackSnapshot.idle();
      _artworkBytes = null;
      _isArtworkLoading = false;
      _shuffleHistory.clear();
    } else {
      _snapshot = _snapshot.copyWith(
        isPlaying: false,
        status: PlaybackStatus.paused,
      );
    }

    notifyListeners();
    unawaited(_savePlaybackState());
  }

  Future<void> deleteTrack(MusicFile track) async {
    final success = await _deviceMusicService.deleteMusicFile(track.uri);
    if (!success) return;

    // If currently playing the track being deleted, stop playback
    if (currentTrack?.id == track.id) {
      await stopPlayback(clearSelection: true);
    }

    // Remove from queue and refresh indices
    final updatedQueue = _queue.where((item) => item.id != track.id).toList();
    _artworkCache.remove(track.id);
    _artworkLoadingTrackIds.remove(track.id);

    setQueue(updatedQueue);
  }

  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;
    if (!_isShuffleEnabled) {
      _shuffleHistory.clear();
    }
    notifyListeners();
  }

  Future<void> ensureArtworkLoaded(MusicFile track) async {
    final trackId = track.id;
    if (_artworkCache.containsKey(trackId) ||
        _artworkLoadingTrackIds.contains(trackId)) {
      return;
    }

    _artworkLoadingTrackIds.add(trackId);
    notifyListeners();

    try {
      final bytes = await _deviceMusicService.fetchArtwork(track);
      _artworkCache[trackId] = bytes;
      if (currentTrack?.id == trackId) {
        _artworkBytes = bytes;
      }
    } catch (_) {
      _artworkCache[trackId] = null;
      if (currentTrack?.id == trackId) {
        _artworkBytes = null;
      }
    } finally {
      _artworkLoadingTrackIds.remove(trackId);
      if (currentTrack?.id == trackId) {
        _isArtworkLoading = false;
      }
      notifyListeners();
    }
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    notifyListeners();
  }

  void _handlePlaybackEvent(PlaybackSnapshot event) {
    final previousTrackId = _snapshot.trackId;
    final previousPosition = _snapshot.positionMs;
    _snapshot = event;

    if (event.trackId != null) {
      final updatedIndex = _queue.indexWhere(
        (song) => song.id == event.trackId,
      );
      if (updatedIndex >= 0 && updatedIndex != _currentIndex) {
        _currentIndex = updatedIndex;
      }
    }

    final track = currentTrack;
    if (track != null && event.trackId != previousTrackId) {
      _setArtworkForTrack(track);
      unawaited(_loadArtwork(track));
    }

    if (event.status == PlaybackStatus.completed && !_isAutoAdvancing) {
      _isAutoAdvancing = true;
      unawaited(
        _handleTrackCompletion().whenComplete(() {
          _isAutoAdvancing = false;
        }),
      );
    }

    // Save state if position changed significantly
    if (event.trackId != previousTrackId ||
        (event.positionMs - previousPosition).abs() > 1000) {
      unawaited(_savePlaybackState());
    }

    notifyListeners();
  }

  Future<void> _handleTrackCompletion() async {
    if (_repeatMode == RepeatMode.one) {
      await _deviceMusicService.resumePlayback();
      return;
    }

    if (_isShuffleEnabled && _queue.length > 1) {
      await _playTrackAt(_randomNextIndex());
      return;
    }

    if (_currentIndex >= 0 && _currentIndex < _queue.length - 1) {
      await _playTrackAt(_currentIndex + 1);
      return;
    }

    if (_repeatMode == RepeatMode.all && _queue.isNotEmpty) {
      await _playTrackAt(0);
      return;
    }

    _snapshot = _snapshot.copyWith(isPlaying: false);
    notifyListeners();
  }

  int _randomNextIndex() {
    if (_queue.isEmpty || _queue.length == 1) {
      return 0;
    }

    var nextIndex = _currentIndex;
    while (nextIndex == _currentIndex) {
      nextIndex = _random.nextInt(_queue.length);
    }
    return nextIndex;
  }

  void _setArtworkForTrack(MusicFile track) {
    if (_artworkCache.containsKey(track.id)) {
      _artworkBytes = _artworkCache[track.id];
      _isArtworkLoading = false;
      _artworkLoadingTrackIds.remove(track.id);
      return;
    }

    _artworkBytes = null;
    _isArtworkLoading = true;
    _artworkLoadingTrackIds.add(track.id);
  }

  Future<void> _loadArtwork(MusicFile track) async {
    if (_artworkCache.containsKey(track.id)) {
      _artworkBytes = _artworkCache[track.id];
      _isArtworkLoading = false;
      _artworkLoadingTrackIds.remove(track.id);
      notifyListeners();
      return;
    }

    _isArtworkLoading = true;
    _artworkLoadingTrackIds.add(track.id);
    notifyListeners();
    final trackId = track.id;

    try {
      final bytes = await _deviceMusicService.fetchArtwork(track);
      _artworkCache[trackId] = bytes;
      if (currentTrack?.id == trackId) {
        _artworkBytes = bytes;
      }
    } catch (_) {
      _artworkCache[trackId] = null;
      if (currentTrack?.id == trackId) {
        _artworkBytes = null;
      }
    } finally {
      _artworkLoadingTrackIds.remove(trackId);
      if (currentTrack?.id == trackId) {
        _isArtworkLoading = false;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _remoteCommandSubscription?.cancel();
    _uiCommandController.close();
    super.dispose();
  }

  Future<void> _handleRemoteCommand(String command) async {
    switch (command) {
      case 'next':
        await playNext();
      case 'previous':
        await playPrevious();
      case 'togglePlayback':
        await togglePlayback();
      case 'stop':
        await stopPlayback();
      case 'expandPlayer':
        _uiCommandController.add('expandPlayer');
    }
  }

  Future<void> _extractPalette(MusicFile track) async {
    final artwork = artworkForTrack(track);
    if (artwork == null) {
      _currentPalette = null;
      notifyListeners();
      return;
    }

    try {
      _currentPalette = await PaletteGenerator.fromImageProvider(
        MemoryImage(artwork),
        maximumColorCount: 20,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error extracting palette: $e');
      _currentPalette = null;
      notifyListeners();
    }
  }

  void _syncNativeQueue() {
    unawaited(_deviceMusicService.syncQueue(_queue, _currentIndex));
  }
}

enum RepeatMode { off, all, one }
