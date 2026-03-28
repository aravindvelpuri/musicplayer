import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../models/music_file.dart';
import '../models/playback_snapshot.dart';

class DeviceMusicService {
  DeviceMusicService() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.aravindprojects.musicplayer/media',
  );
  static const EventChannel _events = EventChannel(
    'com.aravindprojects.musicplayer/player_events',
  );
  final StreamController<String> _remoteCommandController =
      StreamController<String>.broadcast();

  Future<List<MusicFile>> fetchMusicFiles() async {
    final rawResult = await _channel.invokeMethod<List<dynamic>>(
      'getMusicFiles',
    );
    final result = rawResult ?? <dynamic>[];

    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(MusicFile.fromMap)
        .toList(growable: false);
  }

  Future<void> playTrack(MusicFile track) {
    return _channel.invokeMethod<void>('playTrack', <String, Object?>{
      'id': track.id,
      'uri': track.uri,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
    });
  }

  Future<void> pausePlayback() {
    return _channel.invokeMethod<void>('pausePlayback');
  }

  Future<void> resumePlayback() {
    return _channel.invokeMethod<void>('resumePlayback');
  }

  Future<void> seekTo(int positionMs) {
    return _channel.invokeMethod<void>('seekTo', <String, Object?>{
      'positionMs': positionMs,
    });
  }

  Future<void> stopPlayback() {
    return _channel.invokeMethod<void>('stopPlayback');
  }

  Future<Uint8List?> fetchArtwork(MusicFile track) {
    return _channel.invokeMethod<Uint8List>('getArtwork', <String, Object?>{
      'uri': track.uri,
    });
  }

  Future<bool> deleteMusicFile(String uri) async {
    try {
      final bool? success = await _channel.invokeMethod('deleteMusicFile', {'uri': uri});
      return success ?? false;
    } catch (e) {
      debugPrint('Error deleting music file: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getEqualizerBands() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod('getEqualizerBands');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('Error getting equalizer bands: $e');
      return null;
    }
  }

  Future<bool> setEqualizerBandLevel(int bandIndex, int level) async {
    try {
      final bool? success = await _channel.invokeMethod('setEqualizerBandLevel', {
        'bandIndex': bandIndex,
        'level': level,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error setting equalizer band level: $e');
      return false;
    }
  }

  Future<bool> setEqualizerEnabled(bool enabled) async {
    try {
      final bool? success = await _channel.invokeMethod('setEqualizerEnabled', {
        'enabled': enabled,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Error setting equalizer enabled: $e');
      return false;
    }
  }

  Future<void> syncQueue(List<MusicFile> queue, int index) async {
    try {
      await _channel.invokeMethod('syncQueue', {
        'tracks': queue.map((f) => f.toMap()).toList(),
        'index': index,
      });
    } catch (e) {
      debugPrint('Error syncing queue: $e');
    }
  }

  Stream<PlaybackSnapshot> playerEvents() {
    return _events.receiveBroadcastStream().map((dynamic event) {
      if (event is Map<dynamic, dynamic>) {
        return PlaybackSnapshot.fromMap(event);
      }
      return PlaybackSnapshot.idle();
    });
  }

  Stream<String> remoteCommands() => _remoteCommandController.stream;

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method != 'remoteCommand') {
      return;
    }

    final arguments = call.arguments;
    if (arguments is Map<dynamic, dynamic>) {
      final command = arguments['command'];
      if (command is String && command.isNotEmpty) {
        _remoteCommandController.add(command);
      }
    }
  }
}
