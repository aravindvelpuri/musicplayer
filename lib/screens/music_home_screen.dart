import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/local_music_player_controller.dart';
import '../models/music_file.dart';
import '../services/device_music_service.dart';
import '../utils/formatters.dart';
import '../widgets/mini_player_bar.dart';
import '../widgets/song_artwork.dart';
import 'now_playing_screen.dart';
import 'about_screen.dart';
import '../main.dart';

class MusicHomeScreen extends StatefulWidget {
  const MusicHomeScreen({super.key});

  @override
  State<MusicHomeScreen> createState() => _MusicHomeScreenState();
}

class _MusicHomeScreenState extends State<MusicHomeScreen> {
  final DeviceMusicService _deviceMusicService = DeviceMusicService();
  late final LocalMusicPlayerController _playerController;
  late PageController _pageController;

  bool _isLoading = true;
  bool _isPlayerExpanded = false;
  bool _permissionDenied = false;
  String? _errorMessage;
  _LibraryFilter _selectedFilter = _LibraryFilter.all;
  String? _selectedFolderPath;
  String? _selectedMovieName;
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
    _loadMusicFiles();
  }

  @override
  void dispose() {
    _playerController.dispose();
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Track?'),
        content: Text('Are you sure you want to permanently delete "${track.title}" from your device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
                SafeArea(
                  bottom: false,
                  child: GestureDetector(
                    onTap: () {
                      if (_isSearching) {
                        FocusScope.of(context).unfocus();
                        _toggleSearch();
                      }
                      if (_expandedTrackId != null) {
                        setState(() {
                          _expandedTrackId = null;
                        });
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
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
                                scale: Tween<double>(begin: 0.95, end: 1.0)
                                    .animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _isSearching
                              ? Container(
                                  key: const ValueKey('search-bar'),
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
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
                                      hintStyle:
                                          theme.textTheme.bodyLarge?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.6),
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
                                              icon: const Icon(
                                                  Icons.close_rounded),
                                              iconSize: 20,
                                            ),
                                          IconButton(
                                            onPressed: _toggleSearch,
                                            icon: const Icon(
                                                Icons.keyboard_arrow_up_rounded),
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : Row(
                                  key: const ValueKey('title-bar'),
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(
                                        'Library',
                                        style: theme.textTheme.headlineLarge
                                            ?.copyWith(
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
                                            backgroundColor: theme.colorScheme
                                                .surfaceContainerHighest,
                                            foregroundColor:
                                                theme.colorScheme.primary,
                                            padding: const EdgeInsets.all(12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const AboutScreen(),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.info_outline_rounded),
                                          style: IconButton.styleFrom(
                                            backgroundColor: theme.colorScheme
                                                .surfaceContainerHighest,
                                            foregroundColor:
                                                theme.colorScheme.primary,
                                            padding: const EdgeInsets.all(12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                                      onTap: () =>
                                          _selectFilter(_LibraryFilter.all),
                                    ),
                                    const SizedBox(width: 12),
                                    _LibraryFilterCard(
                                      label: 'Folders',
                                      isSelected: _selectedFilter ==
                                          _LibraryFilter.folders,
                                      onTap: () =>
                                          _selectFilter(_LibraryFilter.folders),
                                    ),
                                    const SizedBox(width: 12),
                                    _LibraryFilterCard(
                                      label: 'Movies',
                                      isSelected: _selectedFilter ==
                                          _LibraryFilter.movies,
                                      onTap: () =>
                                          _selectFilter(_LibraryFilter.movies),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: const PageScrollPhysics(
                            parent: ClampingScrollPhysics(),
                          ),
                          onPageChanged: (index) {
                            setState(() {
                              _selectedFilter = _LibraryFilter.values[index];
                            });
                          },
                          children: [
                            // Page 0: All Songs
                            RefreshIndicator(
                              onRefresh: _loadMusicFiles,
                              child: filteredFiles.isEmpty && _isSearching
                                  ? _buildNoResultsView(theme)
                                  : _buildLibrary(
                                      theme: theme,
                                      tracks: filteredFiles,
                                    ),
                            ),
                            // Page 1: Folders
                            activeFolder == null
                                ? (folderGroups.isEmpty && _isSearching
                                    ? _buildNoResultsView(theme)
                                    : _buildCategoryGrid(
                                        categories: folderGroups.map((f) => (
                                              name: f.name,
                                              info: '${f.tracks.length} songs',
                                              tracks: f.tracks,
                                              onTap: () {
                                                setState(() {
                                                  _selectedFolderPath = f.path;
                                                  _expandedTrackId = null;
                                                });
                                              },
                                            )).toList(),
                                        icon: Icons.music_note_rounded,
                                        theme: theme,
                                      ))
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 12),
                                        child: _buildCategoryHeader(
                                          title: activeFolder.name,
                                          subtitle:
                                              '${activeFolder.tracks.length} songs',
                                          icon: Icons.folder_open_rounded,
                                          theme: theme,
                                          onBack: () => setState(() =>
                                              _selectedFolderPath = null),
                                        ),
                                      ),
                                      Expanded(
                                        child: RefreshIndicator(
                                          onRefresh: _loadMusicFiles,
                                          child: _buildLibrary(
                                            theme: theme,
                                            tracks: activeFolder.tracks,
                                            activeFolder: activeFolder,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            // Page 2: Movies
                            activeMovie == null
                                ? (movieGroups.isEmpty && _isSearching
                                    ? _buildNoResultsView(theme)
                                    : _buildCategoryGrid(
                                        categories: movieGroups.map((m) => (
                                              name: m.name,
                                              info: '${m.tracks.length} songs',
                                              tracks: m.tracks,
                                              onTap: () {
                                                setState(() {
                                                  _selectedMovieName = m.name;
                                                  _expandedTrackId = null;
                                                });
                                              },
                                            )).toList(),
                                        icon: Icons.movie_rounded,
                                        theme: theme,
                                      ))
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 0, 16, 12),
                                        child: _buildCategoryHeader(
                                          title: activeMovie.name,
                                          subtitle:
                                              '${activeMovie.tracks.length} songs',
                                          icon: Icons.movie_outlined,
                                          theme: theme,
                                          onBack: () => setState(() =>
                                              _selectedMovieName = null),
                                        ),
                                      ),
                                      Expanded(
                                        child: RefreshIndicator(
                                          onRefresh: _loadMusicFiles,
                                          child: _buildLibrary(
                                            theme: theme,
                                            tracks: activeMovie.tracks,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            'Version ${AppConfig.version}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasTrack)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !showExpandedPlayer,
                      child: AnimatedOpacity(
                        opacity: showExpandedPlayer ? 1 : 0,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: AnimatedScale(
                          scale: showExpandedPlayer ? 1 : 0.96,
                          alignment: Alignment.bottomCenter,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          child: AnimatedSlide(
                            offset: showExpandedPlayer
                                ? Offset.zero
                                : const Offset(0, 0.08),
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
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
        final firstTrackWithArtwork = cat.tracks.firstWhere(
          (t) => _playerController.artworkForTrack(t) != null,
          orElse: () => cat.tracks.first,
        );

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
      ],
    );
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
                              itemCount: tracks.length,
                              itemBuilder: (context, index) {
                                final musicFile = tracks[index];
                                final isCurrent = _playerController.currentTrack?.id ==
                                    musicFile.id;
                                final isPlayingCurrent = isCurrent &&
                                    _playerController.isPlaying;
                                final isExpanded = _expandedTrackId == musicFile.id;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Material(
                                        color: isCurrent
                                            ? theme.colorScheme.primaryContainer.withValues(alpha: (0.12))
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
                                                  albumName: _selectedFilter == _LibraryFilter.movies ? _selectedMovieName : null,
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
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        musicFile.title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: theme.textTheme.titleMedium
                                                            ?.copyWith(
                                                          fontWeight: FontWeight.w700,
                                                          color: isCurrent
                                                              ? theme.colorScheme.primary
                                                              : theme.colorScheme
                                                                  .onSurface,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        '${musicFile.artist} | ${musicFile.album}',
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: theme.textTheme.bodyMedium,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        _selectedFilter ==
                                                                _LibraryFilter.folders
                                                            ? (musicFile.displayName
                                                                    .isNotEmpty
                                                                ? musicFile.displayName
                                                                : musicFile.pathLabel)
                                                            : musicFile.pathLabel,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style: theme.textTheme.bodySmall,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    if (musicFile.durationMs > 0)
                                                      Text(
                                                        formatDuration(
                                                            musicFile.durationMs),
                                                        style:
                                                            theme.textTheme.labelMedium,
                                                      ),
                                                    const SizedBox(height: 10),
                                                    AnimatedContainer(
                                                      duration: const Duration(
                                                          milliseconds: 220),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isCurrent
                                                            ? theme.colorScheme
                                                                .secondaryContainer
                                                            : const Color(0xFFF1F4F2),
                                                        borderRadius:
                                                            BorderRadius.circular(999),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            isPlayingCurrent
                                                                ? Icons.graphic_eq
                                                                : Icons.play_arrow_rounded,
                                                            size: 16,
                                                            color: isCurrent
                                                                ? theme.colorScheme
                                                                    .onSecondaryContainer
                                                                : theme.colorScheme
                                                                    .onSurfaceVariant,
                                                          ),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            isCurrent
                                                                ? (_playerController
                                                                        .isPlaying
                                                                    ? 'Playing'
                                                                    : 'Paused')
                                                                : 'Play',
                                                            style: theme.textTheme
                                                                .labelMedium
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight.w700,
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
                                        Material(
                                          color: theme.colorScheme.error,
                                          borderRadius: const BorderRadius.vertical(
                                            bottom: Radius.circular(22),
                                          ),
                                          elevation: 4,
                                          child: InkWell(
                                            onTap: () =>
                                                _handleDeleteTrack(musicFile),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                              bottom: Radius.circular(22),
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 12),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline_rounded,
                                                    color: theme.colorScheme.onError,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    'Delete Track',
                                                    style: theme.textTheme.titleMedium
                                                        ?.copyWith(
                                                      color: theme.colorScheme.onError,
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

enum _LibraryFilter { all, folders, movies }

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
    required this.trackForArtwork,
    required this.controller,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final String info;
  final MusicFile trackForArtwork;
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
    required this.track,
    required this.controller,
    required this.fallbackIcon,
  });

  final MusicFile track;
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
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final artwork = widget.controller.artworkForTrack(widget.track);
        final isLoading =
            widget.controller.isArtworkLoadingForTrack(widget.track);

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
