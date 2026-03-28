import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/local_music_player_controller.dart';
import '../models/music_file.dart';
import '../services/device_music_service.dart';
import '../utils/formatters.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/song_artwork.dart';
import '../widgets/custom_alert.dart';
import 'now_playing_screen.dart';
import 'about_screen.dart';
import '../main.dart';
import '../models/playlist.dart';
import '../services/playlist_service.dart';

class MusicHomeScreen extends StatefulWidget {
  const MusicHomeScreen({super.key});

  @override
  State<MusicHomeScreen> createState() => _MusicHomeScreenState();
}

class _MusicHomeScreenState extends State<MusicHomeScreen> {
  final DeviceMusicService _deviceMusicService = DeviceMusicService();
  late final LocalMusicPlayerController _playerController;
  late PageController _pageController;
  final PlaylistService _playlistService = PlaylistService();
  List<Playlist> _playlists = [];
  StreamSubscription<String>? _uiCommandSubscription;

  bool _isLoading = true;
  bool _isPlayerExpanded = false;
  bool _permissionDenied = false;
  String? _errorMessage;
  _LibraryFilter _selectedFilter = _LibraryFilter.all;
  String? _selectedFolderPath;
  String? _selectedMovieName;
  String? _selectedPlaylistId;
  String? _playbackFolderPath;
  List<MusicFile> _musicFiles = const <MusicFile>[];
  String? _expandedTrackId;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _playerController = LocalMusicPlayerController(_deviceMusicService);
    _pageController = PageController(initialPage: _selectedFilter.index);
    _uiCommandSubscription = _playerController.uiCommands.listen((command) {
      if (command == 'expandPlayer') {
        _expandNowPlaying();
      }
    });
    _loadMusicFiles();
  }

  @override
  void dispose() {
    _playerController.dispose();
    _uiCommandSubscription?.cancel();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  Future<void> _loadMusicFiles() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
      _errorMessage = null;
    });

    try {
      final musicFiles = await _deviceMusicService.fetchMusicFiles();
      final playlists = await _playlistService.getPlaylists();
      
      if (!mounted) {
        return;
      }

      final folderGroups = _buildFolderGroups(musicFiles);
      final resolvedSelectedFolderPath = _resolveFolderPath(
        folderGroups,
        _selectedFolderPath,
      );
      final resolvedPlaybackFolderPath = _playerController.currentTrack == null
          ? null
          : _resolveFolderPath(folderGroups, _playbackFolderPath);

      setState(() {
        _musicFiles = musicFiles;
        _playlists = playlists;
        _selectedFolderPath = resolvedSelectedFolderPath;
        _playbackFolderPath = resolvedPlaybackFolderPath;
      });
      _playerController.setQueue(
        _queueForPlaybackContext(musicFiles, resolvedPlaybackFolderPath),
      );
      // Restore playback state after files are loaded
      unawaited(_playerController.restoreState(musicFiles));
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _musicFiles = const <MusicFile>[];
        _permissionDenied = error.code == 'permission_denied';
        _errorMessage = _permissionDenied
            ? 'Music access permission is required to read songs from the device.'
            : (error.message ?? 'Unable to fetch music files.');
        _selectedFolderPath = null;
        _playbackFolderPath = null;
      });
      _playerController.setQueue(const <MusicFile>[]);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _musicFiles = const <MusicFile>[];
        _errorMessage = 'Something went wrong while reading music files.';
        _selectedFolderPath = null;
        _playbackFolderPath = null;
      });
      _playerController.setQueue(const <MusicFile>[]);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _playAndOpen(
    List<MusicFile> playlist,
    int index, {
    String? folderPath,
    String? albumName,
  }) {
    _playerController.setQueue(
      playlist,
      initialIndex: index,
      playbackContext: folderPath ?? albumName,
    );
    _expandNowPlaying();
  }

  Future<void> _handleDeleteTrack(MusicFile track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppCustomAlert(
        title: 'Delete Track?',
        content: 'Are you sure you want to permanently delete "${track.title}" from your device?',
        isDestructive: true,
        actions: [
          AppAlertAction(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          AppAlertAction(
            label: 'Delete',
            isPrimary: true,
            isDestructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _playerController.deleteTrack(track);
      setState(() {
        _expandedTrackId = null;
        _musicFiles = _musicFiles.where((f) => f.id != track.id).toList();
      });
      _showMessage('Track deleted.');
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Failed to delete track.');
    } catch (_) {
      _showMessage('Failed to delete track.');
    }
  }

  void _expandNowPlaying() {
    if (_playerController.currentTrack == null) {
      return;
    }

    setState(() {
      _isPlayerExpanded = true;
    });
  }

  void _minimizeNowPlaying() {
    if (!_isPlayerExpanded) {
      return;
    }

    setState(() {
      _isPlayerExpanded = false;
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectFilter(_LibraryFilter filter) {
    if (_selectedFilter == filter) {
      return;
    }

    final folderGroups = _buildFolderGroups(_musicFiles);
    final movieGroups = _buildMovieGroups(_musicFiles);

    setState(() {
      _selectedFilter = filter;
      if (filter == _LibraryFilter.folders) {
        _selectedFolderPath = _resolveFolderPath(
          folderGroups,
          _selectedFolderPath,
        );
      } else if (filter == _LibraryFilter.movies) {
        _selectedMovieName = _resolveMovieName(
          movieGroups,
          _selectedMovieName,
        );
      } else if (filter == _LibraryFilter.playlists) {
        _selectedPlaylistId = _resolvePlaylistId(
          _playlists,
          _selectedPlaylistId,
        );
      }
    });

    _pageController.animateToPage(
      filter.index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  List<_FolderGroup> _buildFolderGroups(List<MusicFile> tracks) {
    final groupedTracks = <String, List<MusicFile>>{};
    final folderNames = <String, String>{};

    for (final track in tracks) {
      final folderPath = track.folderPath.isNotEmpty
          ? track.folderPath
          : '__unknown_folder__';
      groupedTracks.putIfAbsent(folderPath, () => <MusicFile>[]).add(track);
      folderNames.putIfAbsent(folderPath, () => track.folderName);
    }

    final groups =
        groupedTracks.entries.map((entry) {
          final sortedTracks = List<MusicFile>.of(entry.value)
            ..sort(
              (left, right) =>
                  left.title.toLowerCase().compareTo(right.title.toLowerCase()),
            );

          return _FolderGroup(
            path: entry.key,
            name: folderNames[entry.key] ?? 'Unknown folder',
            tracks: sortedTracks,
          );
        }).toList()..sort(
          (left, right) =>
              left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        );
    return groups;
  }

  List<_MovieGroup> _buildMovieGroups(List<MusicFile> tracks) {
    if (tracks.isEmpty) {
      return const [];
    }
    final Map<String, List<MusicFile>> groupsMap = {};
    for (final track in tracks) {
      final album = track.album;
      if (!groupsMap.containsKey(album)) {
        groupsMap[album] = [];
      }
      groupsMap[album]!.add(track);
    }

    final groups = groupsMap.entries.map((entry) {
      final sortedTracks = List<MusicFile>.from(entry.value)
        ..sort(
          (left, right) =>
              left.title.toLowerCase().compareTo(right.title.toLowerCase()),
        );
      return _MovieGroup(
        name: entry.key,
        tracks: sortedTracks,
      );
    }).toList()..sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );

    return groups;
  }

  String? _resolveFolderPath(
    List<_FolderGroup> folderGroups,
    String? folderPath,
  ) {
    if (folderPath != null &&
        folderGroups.any((group) => group.path == folderPath)) {
      return folderPath;
    }
    return null;
  }

  String? _resolveMovieName(
    List<_MovieGroup> movieGroups,
    String? movieName,
  ) {
    if (movieName != null &&
        movieGroups.any((group) => group.name == movieName)) {
      return movieName;
    }
    return null;
  }

  String? _resolvePlaylistId(
    List<Playlist> playlists,
    String? playlistId,
  ) {
    if (playlistId != null &&
        playlists.any((p) => p.id == playlistId)) {
      return playlistId;
    }
    return null;
  }

  List<MusicFile> _queueForPlaybackContext(
    List<MusicFile> allTracks,
    String? playbackContext,
  ) {
    if (playbackContext == null) {
      return allTracks;
    }

    // Check if playbackContext is a folder path
    for (final group in _buildFolderGroups(allTracks)) {
      if (group.path == playbackContext) {
        return group.tracks;
      }
    }

    // Check if playbackContext is an album name
    for (final group in _buildMovieGroups(allTracks)) {
      if (group.name == playbackContext) {
        return group.tracks;
      }
    }

    return allTracks;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredFiles = _musicFiles.where((file) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return file.title.toLowerCase().contains(query) ||
          file.artist.toLowerCase().contains(query) ||
          file.album.toLowerCase().contains(query) ||
          file.folderName.toLowerCase().contains(query);
    }).toList();

    final folderGroups = _buildFolderGroups(filteredFiles);
    final activeFolderPath = _resolveFolderPath(
      folderGroups,
      _selectedFolderPath,
    );
    final activeFolder = activeFolderPath == null
        ? null
        : folderGroups.cast<_FolderGroup?>().firstWhere(
            (group) => group?.path == activeFolderPath,
            orElse: () => null,
          );

    final movieGroups = _buildMovieGroups(filteredFiles);
    final activeMovieName = _resolveMovieName(
      movieGroups,
      _selectedMovieName,
    );

    final activeMovie = activeMovieName == null
        ? null
        : movieGroups.cast<_MovieGroup?>().firstWhere(
            (m) => m?.name == activeMovieName,
            orElse: () => null,
          );

    final activePlaylist = _selectedPlaylistId == null
        ? null
        : _playlists.cast<Playlist?>().firstWhere(
            (p) => p?.id == _selectedPlaylistId,
            orElse: () => null,
          );

    return ListenableBuilder(
      listenable: _playerController,
      builder: (context, _) {
        final hasTrack = _playerController.currentTrack != null;
        final showExpandedPlayer = hasTrack && _isPlayerExpanded;

        return PopScope(
          canPop: !showExpandedPlayer,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && showExpandedPlayer) {
              _minimizeNowPlaying();
            }
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            child: Scaffold(
              body: Stack(
                children: [
                  // Phase 0: The Sheet (Main Content)
                  AnimatedScale(
                    scale: showExpandedPlayer ? 0.94 : 1.0,
                    alignment: Alignment.topCenter,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutQuart,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutQuart,
                      foregroundDecoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: showExpandedPlayer ? 0.45 : 0.0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          showExpandedPlayer ? 32 : 0,
                        ),
                        child: Scaffold(
                          body: SafeArea(
                            bottom: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildLibraryHeader(theme),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              _LibraryFilterCard(
                                                label: 'All',
                                                isSelected: _selectedFilter ==
                                                    _LibraryFilter.all,
                                                onTap: () => _selectFilter(
                                                    _LibraryFilter.all),
                                              ),
                                              const SizedBox(width: 12),
                                              _LibraryFilterCard(
                                                label: 'Folders',
                                                isSelected: _selectedFilter ==
                                                    _LibraryFilter.folders,
                                                onTap: () => _selectFilter(
                                                    _LibraryFilter.folders),
                                              ),
                                              const SizedBox(width: 12),
                                              _LibraryFilterCard(
                                                label: 'Movies',
                                                isSelected: _selectedFilter ==
                                                    _LibraryFilter.movies,
                                                onTap: () => _selectFilter(
                                                    _LibraryFilter.movies),
                                              ),
                                              const SizedBox(width: 12),
                                              _LibraryFilterCard(
                                                label: 'Playlists',
                                                isSelected: _selectedFilter ==
                                                    _LibraryFilter.playlists,
                                                onTap: () => _selectFilter(
                                                    _LibraryFilter.playlists),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: IndexedStack(
                                    index: _selectedFilter.index,
                                    children: [
                                      _buildLibrary(
                                        theme: theme,
                                        tracks: _musicFiles,
                                      ),
                                      activeFolder == null
                                          ? _buildFolderGrid(theme)
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                          16, 0, 16, 12),
                                                  child: _buildCategoryHeader(
                                                    title: activeFolder.name,
                                                    subtitle:
                                                        '${activeFolder.tracks.length} songs',
                                                    icon: Icons.folder_rounded,
                                                    theme: theme,
                                                    onBack: () => setState(() =>
                                                        _selectedFolderPath =
                                                            null),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: RefreshIndicator(
                                                    onRefresh: _loadMusicFiles,
                                                    child: _buildLibrary(
                                                      theme: theme,
                                                      tracks:
                                                          activeFolder.tracks,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                      activeMovie == null
                                          ? _buildMovieGrid(theme)
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                          16, 0, 16, 12),
                                                  child: _buildCategoryHeader(
                                                    title: activeMovie.name,
                                                    subtitle:
                                                        '${activeMovie.tracks.length} songs',
                                                    icon: Icons.movie_rounded,
                                                    theme: theme,
                                                    onBack: () => setState(() =>
                                                        _selectedMovieName =
                                                            null),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: RefreshIndicator(
                                                    onRefresh: _loadMusicFiles,
                                                    child: _buildLibrary(
                                                      theme: theme,
                                                      tracks:
                                                          activeMovie.tracks,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                      activePlaylist == null
                                          ? _buildPlaylistGrid(theme)
                                          : Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                          16, 0, 16, 12),
                                                  child: _buildCategoryHeader(
                                                    title: activePlaylist.name,
                                                    subtitle:
                                                        '${activePlaylist.trackIds.length} songs',
                                                    icon: Icons
                                                        .playlist_play_rounded,
                                                    theme: theme,
                                                    onBack: () => setState(() =>
                                                        _selectedPlaylistId =
                                                            null),
                                                    trailing: IconButton(
                                                      onPressed: () =>
                                                          _deletePlaylist(
                                                              activePlaylist),
                                                      icon: const Icon(Icons
                                                          .delete_outline_rounded),
                                                      color: theme
                                                          .colorScheme.error,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: _buildPlaylistSongs(
                                                    theme: theme,
                                                    playlist: activePlaylist,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hasTrack)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !showExpandedPlayer,
                        child: AnimatedOpacity(
                          opacity: showExpandedPlayer ? 1 : 0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutQuart,
                          child: AnimatedScale(
                            scale: showExpandedPlayer ? 1 : 0.90,
                            alignment: Alignment.bottomCenter,
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutQuart,
                            child: AnimatedSlide(
                              offset: showExpandedPlayer
                                  ? Offset.zero
                                  : const Offset(0, 0.6),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOutQuart,
                              child: NowPlayingPanel(
                                controller: _playerController,
                                onMinimize: _minimizeNowPlaying,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              bottomNavigationBar: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                reverseDuration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, 0.22),
                    end: Offset.zero,
                  ).animate(animation);

                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: offsetAnimation,
                      child: child,
                    ),
                  );
                },
                child: hasTrack && !showExpandedPlayer
                    ? MiniPlayerBar(
                        key: const ValueKey('mini-player'),
                        controller: _playerController,
                        onOpen: _expandNowPlaying,
                      )
                    : const SizedBox.shrink(key: ValueKey('mini-player-hidden')),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLibraryHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        child: _isSearching
            ? Container(
                key: const ValueKey('search-bar'),
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(26),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (value) => setState(() {
                    _searchQuery = value;
                  }),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 0,
                    ),
                    hintText: 'Search songs, folders...',
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      color:
                          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.close_rounded),
                            iconSize: 20,
                          ),
                        IconButton(
                          onPressed: _toggleSearch,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              )
            : Row(
                key: const ValueKey('title-bar'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Library',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _toggleSearch,
                        icon: const Icon(Icons.search_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const AboutScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.info_outline_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: theme.colorScheme.primary,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFolderGrid(ThemeData theme) {
    final filteredFiles = _musicFiles.where((file) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return file.title.toLowerCase().contains(query) ||
          file.artist.toLowerCase().contains(query) ||
          file.folderName.toLowerCase().contains(query);
    }).toList();
    final folderGroups = _buildFolderGroups(filteredFiles);

    return _buildCategoryGrid(
      categories: folderGroups
          .map((f) => (
                name: f.name,
                info: '${f.tracks.length} songs',
                tracks: f.tracks,
                onTap: () {
                  setState(() {
                    _selectedFolderPath = f.path;
                    _expandedTrackId = null;
                  });
                },
              ))
          .toList(),
      icon: Icons.folder_rounded,
      theme: theme,
    );
  }

  Widget _buildMovieGrid(ThemeData theme) {
    final filteredFiles = _musicFiles.where((file) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return file.title.toLowerCase().contains(query) ||
          file.artist.toLowerCase().contains(query) ||
          file.album.toLowerCase().contains(query);
    }).toList();
    final movieGroups = _buildMovieGroups(filteredFiles);

    return _buildCategoryGrid(
      categories: movieGroups
          .map((m) => (
                name: m.name,
                info: '${m.tracks.length} songs',
                tracks: m.tracks,
                onTap: () {
                  setState(() {
                    _selectedMovieName = m.name;
                    _expandedTrackId = null;
                  });
                },
              ))
          .toList(),
      icon: Icons.movie_rounded,
      theme: theme,
    );
  }

  Widget _buildCategoryGrid({
    required List<
            ({
              String name,
              String info,
              List<MusicFile> tracks,
              VoidCallback onTap
            })>
        categories,
    required IconData icon,
    required ThemeData theme,
  }) {
    if (_isLoading && _musicFiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'No items found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.82,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final firstTrackWithArtwork = cat.tracks.isNotEmpty
            ? cat.tracks.firstWhere(
                (t) => _playerController.artworkForTrack(t) != null,
                orElse: () => cat.tracks.first,
              )
            : null;

        return _CategoryGridItem(
          name: cat.name,
          info: cat.info,
          trackForArtwork: firstTrackWithArtwork,
          controller: _playerController,
          icon: icon,
          onTap: cat.onTap,
        );
      },
    );
  }

  Widget _buildCategoryHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeData theme,
    required VoidCallback onBack,
    Widget? trailing,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Row(
                children: [
                  Icon(icon, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildPlaylistGrid(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildCategoryGrid(
              categories: _playlists
                  .map((p) => (
                        name: p.name,
                        info: '${p.trackIds.length} songs',
                        tracks: _musicFiles
                            .where((m) => p.trackIds.contains(m.id))
                            .toList(),
                        onTap: () {
                          setState(() {
                            _selectedPlaylistId = p.id;
                            _expandedTrackId = null;
                          });
                        },
                      ))
                  .toList(),
              icon: Icons.playlist_add_check_rounded,
              theme: theme,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _showCreatePlaylistDialog,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create New Playlist'),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistSongs({
    required ThemeData theme,
    required Playlist playlist,
  }) {
    final tracks =
        _musicFiles.where((m) => playlist.trackIds.contains(m.id)).toList();
    return _buildLibrary(theme: theme, tracks: tracks);
  }

  Future<void> _showCreatePlaylistDialog() async {
    final controller = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'New Playlist',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Give your new collection a name.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Playlist Name',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Create',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newPlaylist = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        trackIds: [],
        createdAt: DateTime.now(),
      );
      await _playlistService.savePlaylist(newPlaylist);
      await _loadMusicFiles();
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AppCustomAlert(
        title: 'Delete Playlist?',
        content: 'Are you sure you want to delete "${playlist.name}"?',
        isDestructive: true,
        actions: [
          AppAlertAction(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          AppAlertAction(
            label: 'Delete',
            isPrimary: true,
            isDestructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _playlistService.deletePlaylist(playlist.id);
      setState(() {
        _selectedPlaylistId = null;
      });
      await _loadMusicFiles();
    }
  }

  Future<void> _showAddToPlaylistDialog(MusicFile track) async {
    if (_playlists.isEmpty) {
      final create = await showDialog<bool>(
        context: context,
        builder: (context) => AppCustomAlert(
          title: 'No Playlists',
          content: 'You haven\'t created any playlists yet. Would you like to create one now?',
          actions: [
            AppAlertAction(
              label: 'Later',
              onPressed: () => Navigator.pop(context, false),
            ),
            AppAlertAction(
              label: 'Create',
              isPrimary: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

      if (create == true) {
        _showCreatePlaylistDialog();
      }
      return;
    }

    final theme = Theme.of(context);
    final playlistId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add to Playlist',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ListView.builder(
              shrinkWrap: true,
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      leading: Icon(
                        Icons.playlist_add_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        playlist.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${playlist.trackIds.length} tracks'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onTap: () => Navigator.pop(context, playlist.id),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (playlistId != null) {
      await _playlistService.addTrackToPlaylist(playlistId, track.id);
      await _loadMusicFiles();
      _showMessage('Added to playlist.');
      setState(() {
        _expandedTrackId = null;
      });
    }
  }

  Widget _buildLibrary({
    required ThemeData theme,
    required List<MusicFile> tracks,
    _FolderGroup? activeFolder,
  }) {
    if (_isLoading && _musicFiles.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          Icon(
            _permissionDenied ? Icons.lock_outline : Icons.error_outline,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            _permissionDenied
                ? 'Grant storage or audio access when Android prompts you, then pull to refresh or tap the refresh button.'
                : 'Pull down to try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (_musicFiles.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No music files found on this device.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Add some songs to the device and refresh the list.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (_selectedFilter == _LibraryFilter.folders &&
        activeFolder == null &&
        !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No folders available yet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Add music files to the device and refresh the library.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (tracks.isEmpty) {
      if (_searchQuery.isNotEmpty) {
        return _buildNoResultsView(theme);
      }
      return ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          Icon(
            _selectedFilter == _LibraryFilter.folders
                ? Icons.folder_open_rounded
                : Icons.library_music_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _selectedFilter == _LibraryFilter.folders
                ? 'No songs found in this folder.'
                : 'No music files found on this device.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            _selectedFilter == _LibraryFilter.folders
                ? 'Choose another folder or refresh the library.'
                : 'Add some songs to the device and refresh the list.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: tracks.length + 1,
      itemBuilder: (context, index) {
        if (index == tracks.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'Version ${AppConfig.version}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }
        final musicFile = tracks[index];
        final isCurrent = _playerController.currentTrack?.id == musicFile.id;
        final isPlayingCurrent = isCurrent && _playerController.isPlaying;
        final isExpanded = _expandedTrackId == musicFile.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: isCurrent
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(22),
                  bottom: Radius.circular(isExpanded ? 0 : 22),
                ),
                elevation: isExpanded ? 4 : 0,
                child: InkWell(
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(22),
                    bottom: Radius.circular(isExpanded ? 0 : 22),
                  ),
                  onTap: () {
                    if (isExpanded) {
                      setState(() {
                        _expandedTrackId = null;
                      });
                    } else {
                      setState(() {
                        _expandedTrackId = null;
                      });
                      _playAndOpen(
                        tracks,
                        index,
                        folderPath: activeFolder?.path,
                        albumName: _selectedFilter == _LibraryFilter.movies
                            ? _selectedMovieName
                            : null,
                      );
                    }
                  },
                  onLongPress: () {
                    setState(() {
                      _expandedTrackId = isExpanded ? null : musicFile.id;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _LibrarySongArtwork(
                          controller: _playerController,
                          track: musicFile,
                          size: 62,
                          borderRadius: 18,
                          iconSize: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                musicFile.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${musicFile.artist} | ${musicFile.album}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _selectedFilter == _LibraryFilter.folders
                                    ? (musicFile.displayName.isNotEmpty
                                        ? musicFile.displayName
                                        : musicFile.pathLabel)
                                    : musicFile.pathLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (musicFile.durationMs > 0)
                              Text(
                                formatDuration(musicFile.durationMs),
                                style: theme.textTheme.labelMedium,
                              ),
                            const SizedBox(height: 10),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? theme.colorScheme.secondaryContainer
                                    : const Color(0xFFF1F4F2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPlayingCurrent
                                        ? Icons.graphic_eq
                                        : Icons.play_arrow_rounded,
                                    size: 16,
                                    color: isCurrent
                                        ? theme.colorScheme.onSecondaryContainer
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isCurrent
                                        ? (_playerController.isPlaying
                                            ? 'Playing'
                                            : 'Paused')
                                        : 'Play',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isExpanded)
                Column(
                  children: [
                    Material(
                      color: theme.colorScheme.error,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(22),
                      ),
                      elevation: 4,
                      child: InkWell(
                        onTap: () => _handleDeleteTrack(musicFile),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(22),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                color: theme.colorScheme.onError,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Delete Track',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onError,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                      elevation: 4,
                      child: InkWell(
                        onTap: () => _showAddToPlaylistDialog(musicFile),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.playlist_add_rounded,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Add to Playlist',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoResultsView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No matches found',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'We couldn\'t find anything matching "$_searchQuery". Try a different name or artist.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
              });
            },
            icon: const Icon(Icons.backspace_outlined),
            label: const Text('Clear Search'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

enum _LibraryFilter { all, folders, movies, playlists }

class _FolderGroup {
  const _FolderGroup({
    required this.path,
    required this.name,
    required this.tracks,
  });

  final String path;
  final String name;
  final List<MusicFile> tracks;
}

class _MovieGroup {
  const _MovieGroup({
    required this.name,
    required this.tracks,
  });

  final String name;
  final List<MusicFile> tracks;
}

class _LibrarySongArtwork extends StatefulWidget {
  const _LibrarySongArtwork({
    required this.controller,
    required this.track,
    required this.size,
    required this.borderRadius,
    required this.iconSize,
  });

  final LocalMusicPlayerController controller;
  final MusicFile track;
  final double size;
  final double borderRadius;
  final double iconSize;

  @override
  State<_LibrarySongArtwork> createState() => _LibrarySongArtworkState();
}

class _LibrarySongArtworkState extends State<_LibrarySongArtwork> {
  @override
  void initState() {
    super.initState();
    _scheduleArtworkLoad();
  }

  @override
  void didUpdateWidget(covariant _LibrarySongArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.controller != widget.controller) {
      _scheduleArtworkLoad();
    }
  }

  void _scheduleArtworkLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.controller.ensureArtworkLoaded(widget.track);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return SongArtwork(
          bytes: widget.controller.artworkForTrack(widget.track),
          isLoading: widget.controller.isArtworkLoadingForTrack(widget.track),
          size: widget.size,
          borderRadius: widget.borderRadius,
          iconSize: widget.iconSize,
        );
      },
    );
  }
}

class _LibraryFilterCard extends StatelessWidget {
  const _LibraryFilterCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected ? theme.colorScheme.primaryContainer : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryGridItem extends StatelessWidget {
  const _CategoryGridItem({
    required this.name,
    required this.info,
    this.trackForArtwork,
    required this.controller,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final String info;
  final MusicFile? trackForArtwork;
  final LocalMusicPlayerController controller;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _CategoryArtwork(
                      track: trackForArtwork,
                      controller: controller,
                      fallbackIcon: icon,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    info,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryArtwork extends StatefulWidget {
  const _CategoryArtwork({
    this.track,
    required this.controller,
    required this.fallbackIcon,
  });

  final MusicFile? track;
  final LocalMusicPlayerController controller;
  final IconData fallbackIcon;

  @override
  State<_CategoryArtwork> createState() => _CategoryArtworkState();
}

class _CategoryArtworkState extends State<_CategoryArtwork> {
  @override
  void initState() {
    super.initState();
    _scheduleArtworkLoad();
  }

  @override
  void didUpdateWidget(covariant _CategoryArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id ||
        oldWidget.controller != widget.controller) {
      _scheduleArtworkLoad();
    }
  }

  void _scheduleArtworkLoad() {
    if (widget.track == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.controller.ensureArtworkLoaded(widget.track!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.track == null) {
      return Center(
        child: Icon(
          widget.fallbackIcon,
          size: 48,
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
      );
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final artwork = widget.controller.artworkForTrack(widget.track!);
        final isLoading =
            widget.controller.isArtworkLoadingForTrack(widget.track!);

        if (isLoading) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (artwork == null) {
          return Center(
            child: Icon(
              widget.fallbackIcon,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          );
        }

        return Image.memory(
          artwork,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      },
    );
  }
}
