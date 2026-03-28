import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';

class PlaylistService {
  static const String _prefKeyPlaylists = 'user_playlists';

  Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_prefKeyPlaylists) ?? [];
    return data.map((item) {
      try {
        return Playlist.fromMap(jsonDecode(item) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<Playlist>().toList();
  }

  Future<void> savePlaylist(Playlist playlist) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlist.id);
    
    if (index >= 0) {
      playlists[index] = playlist;
    } else {
      playlists.add(playlist);
    }
    
    await _saveAll(playlists);
  }

  Future<void> deletePlaylist(String id) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _saveAll(playlists);
  }

  Future<void> _saveAll(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final data = playlists.map((p) => jsonEncode(p.toMap())).toList();
    await prefs.setStringList(_prefKeyPlaylists, data);
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = playlists[index];
      if (!playlist.trackIds.contains(trackId)) {
        final updatedTrackIds = List<String>.from(playlist.trackIds)..add(trackId);
        await savePlaylist(playlist.copyWith(trackIds: updatedTrackIds));
      }
    }
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final playlist = playlists[index];
      final updatedTrackIds = List<String>.from(playlist.trackIds)..remove(trackId);
      await savePlaylist(playlist.copyWith(trackIds: updatedTrackIds));
    }
  }
}
