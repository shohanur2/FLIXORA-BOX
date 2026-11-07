import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlixoraApp());
}

const Color bg = Color(0xFF080808);
const Color panel = Color(0xFF191919);
const Color gold = Color(0xFFD6AD45);
const Color goldLight = Color(0xFFFFE5A3);
const Color white = Colors.white;

const String imageBase = 'https://image.tmdb.org/t/p/';
const String apiKey = String.fromEnvironment('TMDB_API_KEY');

class Movie {
  final int id;
  final String title;
  final String year;
  final String overview;
  final String poster;
  final String backdrop;
  final double rating;
  final String releaseDate;

  const Movie({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.rating,
    required this.releaseDate,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    final date = (json['release_date'] ?? '').toString();

    return Movie(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? json['name'] ?? 'Unknown Movie').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : 'N/A',
      releaseDate: date,
      overview: (json['overview'] ?? 'No description available.').toString(),
      poster: (json['poster_path'] ?? '').toString(),
      backdrop: (json['backdrop_path'] ?? '').toString(),
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
    );
  }

  factory Movie.fromCache(Map<String, dynamic> json) {
    return Movie(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? 'Unknown Movie').toString(),
      year: (json['year'] ?? 'N/A').toString(),
      overview: (json['overview'] ?? '').toString(),
      poster: (json['poster'] ?? '').toString(),
      backdrop: (json['backdrop'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      releaseDate: (json['releaseDate'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'year': year,
        'overview': overview,
        'poster': poster,
        'backdrop': backdrop,
        'rating': rating,
        'releaseDate': releaseDate,
      };

  String get posterUrl =>
      poster.isEmpty ? '' : '$imageBase/w500$poster';

  String get backdropUrl =>
      backdrop.isEmpty ? posterUrl : '$imageBase/w1280$backdrop';
}

class InternetService {
  static Future<bool> isOnline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();

      if (connectivity.contains(ConnectivityResult.none)) {
        return false;
      }

      final response = await http
          .get(Uri.parse('https://www.google.com/generate_204'))
          .timeout(const Duration(seconds: 6));

      return response.statusCode == 204 ||
          response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class MovieCache {
  static const String trendingKey = 'flixora_trending';
  static const String popularKey = 'flixora_popular';
  static const String latestKey = 'flixora_latest';
  static const String topRatedKey = 'flixora_top_rated';

  static const String favouritesKey = 'flixora_favourites';
  static const String savedKey = 'flixora_saved';

  static Future<void> saveList(
    String key,
    List<Movie> movies,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final encoded = jsonEncode(
        movies.map((movie) => movie.toJson()).toList(),
      );

      await prefs.setString(key, encoded);
    } catch (_) {}
  }

  static Future<List<Movie>> getList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);

      if (value == null || value.isEmpty) return [];

      final decoded = jsonDecode(value) as List;

      return decoded
          .whereType<Map>()
          .map(
            (item) => Movie.fromCache(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSearch(
    String query,
    List<Movie> movies,
  ) async {
    final key = 'flixora_search_${query.trim().toLowerCase()}';
    await saveList(key, movies);
  }

  static Future<List<Movie>> getSearch(String query) async {
    final key = 'flixora_search_${query.trim().toLowerCase()}';
    return getList(key);
  }

  // Favourite IDs permanently save
  static Future<Set<int>> getFavourites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(favouritesKey) ?? [])
          .map(int.parse)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveFavourites(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        favouritesKey,
        ids.map((id) => id.toString()).toList(),
      );
    } catch (_) {}
  }

  // Saved movie IDs permanently save
  static Future<Set<int>> getSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(savedKey) ?? [])
          .map(int.parse)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveSaved(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        savedKey,
        ids.map((id) => id.toString()).toList(),
      );
    } catch (_) {}
  }
}

class TmdbService {
  static const String base = 'https://api.themoviedb.org/3';

  static Future<List<Movie>> getMovies(String endpoint) async {
    if (apiKey.isEmpty) {
      throw Exception('TMDB API Key is missing.');
    }

    final uri = Uri.parse('$base/$endpoint').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': 'en-US',
        'page': '1',
      },
    );

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('TMDB error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final results = data['results'] as List? ?? [];

    return results
        .whereType<Map>()
        .map(
          (item) => Movie.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<List<Movie>> search(String query) async {
    if (apiKey.isEmpty) {
      throw Exception('TMDB API Key is missing.');
    }

    final uri = Uri.parse('$base/search/movie').replace(
      queryParameters: {
        'api_key': apiKey,
        'query': query,
        'language': 'en-US',
        'page': '1',
        'include_adult': 'false',
      },
    );

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Search failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final results = data['results'] as List? ?? [];

    return results
        .whereType<Map>()
        .map(
          (item) => Movie.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<Map<String, dynamic>> details(int id) async {
    if (apiKey.isEmpty) {
      throw Exception('TMDB API Key is missing.');
    }

    final uri = Uri.parse('$base/movie/$id').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': 'en-US',
      },
    );

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Could not load movie details.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class DownloadTask {
  final int movieId;
  final String title;
  final String poster;
  double progress;
  String status;
  String? filePath;

  DownloadTask({
    required this.movieId,
    required this.title,
    required this.poster,
    this.progress = 0,
    this.status = 'Waiting',
    this.filePath,
  });
}

class DownloadManager {
  static final Dio _dio = Dio();

  static Future<void> download({
    required String url,
    required String fileName,
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) async {
    try {
      final directory = await getApplicationDocumentsDirectory();

      final safeName = fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );

      final path = '${directory.path}/$safeName.mp4';

      await _dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
      );

      onComplete(path);
    } on DioException catch (e) {
      onError(
        e.type == DioExceptionType.cancel
            ? 'Download cancelled'
            : 'Download failed',
      );
    } catch (_) {
      onError('Download failed');
    }
  }
}

class FlixoraApp extends StatelessWidget {
  const FlixoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flixora',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          primary: gold,
          secondary: goldLight,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF111111),
          indicatorColor: gold.withValues(alpha: 0.18),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? gold
                  : Colors.white54,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _sliderController = PageController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _timer;
  Timer? _searchTimer;

  StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription;

  int _slide = 0;
  int _tab = 0;

  String _search = '';
  bool _searchLoading = false;
  String? _searchError;

  bool loading = true;
  bool _online = false;
  bool _connectionKnown = false;
  bool _refreshing = false;

  String? homeError;

  List<Movie> trending = [];
  List<Movie> popular = [];
  List<Movie> latest = [];
  List<Movie> topRated = [];
  List<Movie> searchResults = [];

  final Set<int> _favourites = {};
  final Set<int> _saved = {};
  final List<DownloadTask> _downloads = [];

  @override
  void initState() {
    super.initState();

    _initializeApp();
    _listenToConnectivity();

    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted || _tab != 0 || trending.isEmpty) return;

        _slide = (_slide + 1) % trending.length;

        if (_sliderController.hasClients) {
          _sliderController.animateToPage(
            _slide,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
        }
      },
    );
  }

  Future<void> _initializeApp() async {
    await _loadCachedMovies();
    await _loadSavedPreferences();

    if (!mounted) return;

    final online = await InternetService.isOnline();

    if (!mounted) return;

    setState(() {
      _online = online;
      _connectionKnown = true;
    });

    if (online) {
      await loadHome();
    } else {
      setState(() {
        loading = false;
        if (_allMovies().isEmpty) {
          homeError = 'offline';
        }
      });
    }
  }

  Future<void> _loadSavedPreferences() async {
    final results = await Future.wait([
      MovieCache.getFavourites(),
      MovieCache.getSaved(),
    ]);

    if (!mounted) return;

    setState(() {
      _favourites
        ..clear()
        ..addAll(results[0]);

      _saved
        ..clear()
        ..addAll(results[1]);
    });
  }

  Future<void> _loadCachedMovies() async {
    final results = await Future.wait([
      MovieCache.getList(MovieCache.trendingKey),
      MovieCache.getList(MovieCache.popularKey),
      MovieCache.getList(MovieCache.latestKey),
      MovieCache.getList(MovieCache.topRatedKey),
    ]);

    if (!mounted) return;

    setState(() {
      trending = results[0];
      popular = results[1];
      latest = results[2];
      topRated = results[3];
      loading = false;
      homeError = null;
    });
  }

  void _listenToConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(
      (results) async {
        final hasNetwork =
            !results.contains(ConnectivityResult.none);

        if (!hasNetwork) {
          if (!mounted) return;

          setState(() {
            _online = false;
            _connectionKnown = true;

            if (_allMovies().isEmpty) {
              homeError = 'offline';
            }
          });

          return;
        }

        final online = await InternetService.isOnline();

        if (!mounted) return;

        final wasOffline = !_online;

        setState(() {
          _online = online;
          _connectionKnown = true;
        });

        if (online && wasOffline) {
          await loadHome();

          if (_search.trim().isNotEmpty) {
            searchMovies(_search);
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchTimer?.cancel();
    _connectivitySubscription?.cancel();
    _sliderController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadHome() async {
    if (_refreshing) return;

    _refreshing = true;

    try {
      final online = await InternetService.isOnline();

      if (!mounted) return;

      if (!online) {
        setState(() {
          _online = false;
          loading = false;

          if (_allMovies().isEmpty) {
            homeError = 'offline';
          }
        });

        return;
      }

      setState(() {
        _online = true;
        _connectionKnown = true;
        loading = _allMovies().isEmpty;
        homeError = null;
      });

      final results = await Future.wait([
        TmdbService.getMovies('trending/movie/week'),
        TmdbService.getMovies('movie/popular'),
        TmdbService.getMovies('movie/now_playing'),
        TmdbService.getMovies('movie/top_rated'),
      ]);

      if (!mounted) return;

      setState(() {
        trending = results[0];
        popular = results[1];
        latest = results[2];
        topRated = results[3];
        loading = false;
        homeError = null;
      });

      await Future.wait([
        MovieCache.saveList(MovieCache.trendingKey, trending),
        MovieCache.saveList(MovieCache.popularKey, popular),
        MovieCache.saveList(MovieCache.latestKey, latest),
        MovieCache.saveList(MovieCache.topRatedKey, topRated),
      ]);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;

        if (_allMovies().isEmpty) {
          homeError = e.toString();
        }
      });
    } finally {
      _refreshing = false;
    }
  }

  void searchMovies(String value) {
    _search = value;
    _searchTimer?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });

      return;
    }

    setState(() {
      _searchLoading = true;
      _searchError = null;
    });

    _searchTimer = Timer(
      const Duration(milliseconds: 600),
      () async {
        final query = value.trim();

        final online = await InternetService.isOnline();

        if (!mounted || _search != value) return;

        if (!online) {
          final cached = await MovieCache.getSearch(query);

          if (!mounted || _search != value) return;

          setState(() {
            _online = false;
            searchResults = cached;
            _searchLoading = false;
            _searchError = cached.isEmpty ? 'offline' : null;
          });

          return;
        }

        try {
          final results = await TmdbService.search(query);

          if (!mounted || _search != value) return;

          setState(() {
            _online = true;
            searchResults = results;
            _searchLoading = false;
            _searchError = null;
          });

          await MovieCache.saveSearch(query, results);
        } catch (e) {
          final cached = await MovieCache.getSearch(query);

          if (!mounted || _search != value) return;

          setState(() {
            searchResults = cached;
            _searchLoading = false;
            _searchError = cached.isEmpty ? e.toString() : null;
          });
        }
      },
    );
  }

  Future<void> toggleFavourite(Movie movie) async {
    setState(() {
      if (!_favourites.add(movie.id)) {
        _favourites.remove(movie.id);
      }
    });

    await MovieCache.saveFavourites(_favourites);
  }

  Future<void> toggleSaved(Movie movie) async {
    setState(() {
      if (!_saved.add(movie.id)) {
        _saved.remove(movie.id);
      }
    });

    await MovieCache.saveSaved(_saved);
  }

  Future<void> openMovie(Movie movie) async {
    final online = await InternetService.isOnline();

    if (!mounted) return;

    setState(() {
      _online = online;
      _connectionKnown = true;
    });

    if (!online) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => NoInternetScreen(
            onRetry: () async {
              final connected = await InternetService.isOnline();

              if (!mounted) return false;

              setState(() {
                _online = connected;
                _connectionKnown = true;
              });

              if (connected) {
                await loadHome();
              }

              return connected;
            },
          ),
        ),
      ).then((connected) async {
        if (!mounted) return;

        if (connected == true) {
          await _openMovieDetails(movie);
        }
      });

      return;
    }

    await _openMovieDetails(movie);
  }

  Future<void> _openMovieDetails(Movie movie) async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsScreen(
          movie: movie,
          isFavourite: _favourites.contains(movie.id),
          isSaved: _saved.contains(movie.id),
          onFavourite: () => toggleFavourite(movie),
          onSave: () => toggleSaved(movie),
          onDownload: () => addDownload(movie),
        ),
      ),
    );

    if (mounted) setState(() {});
  }

  void addDownload(Movie movie) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A licensed downloadable video source is not connected yet.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            _homePage(),
            _allPage(),
            DownloadsScreen(downloads: _downloads),
            _savedPage(),
            _profilePage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: gold),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: gold),
            label: 'All Movies',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download, color: gold),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark, color: gold),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: gold),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          const Icon(
            Icons.movie_creation_outlined,
            color: gold,
            size: 31,
          ),
          const SizedBox(width: 9),
          const Text(
            'Flixora',
            style: TextStyle(
              color: gold,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _message('No new notifications'),
            icon: const Icon(Icons.notifications_none, size: 27),
          ),
          IconButton(
            onPressed: () => setState(() => _tab = 4),
            icon: const CircleAvatar(
              backgroundColor: panel,
              child: Icon(Icons.person_outline, color: white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: TextField(
        controller: _searchController,
        onChanged: searchMovies,
        decoration: InputDecoration(
          hintText: 'Search movies...',
          prefixIcon: const Icon(Icons.search, color: gold),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    searchMovies('');
                  },
                  icon: const Icon(Icons.close),
                )
              : null,
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: gold, width: 1),
          ),
        ),
      ),
    );
  }

  Widget _homePage() {
    if (loading && _allMovies().isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: gold),
      );
    }

    if (homeError == 'offline' && _allMovies().isEmpty) {
      return NoInternetScreen(
        onRetry: () async {
          final connected = await InternetService.isOnline();

          if (!mounted) return false;

          setState(() {
            _online = connected;
            _connectionKnown = true;
          });

          if (connected) {
            await loadHome();
          }

          return connected;
        },
        inline: true,
      );
    }

    if (homeError != null && _allMovies().isEmpty) {
      return _errorView(homeError!, loadHome);
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _searchBox()),
        if (_search.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _sectionTitle('Search Results', 'TMDB'),
          ),
          if (_searchLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(color: gold),
                ),
              ),
            )
          else if (_searchError != null)
            SliverToBoxAdapter(
              child: _errorView(
                _searchError!,
                () => searchMovies(_search),
              ),
            )
          else
            _movieGridSliver(searchResults),
        ] else ...[
          SliverToBoxAdapter(
            child: _sectionTitle('Featured', 'PREMIUM CINEMA'),
          ),
          SliverToBoxAdapter(child: _heroSlider()),
          SliverToBoxAdapter(
            child: _movieSection('Trending Now', trending),
          ),
          SliverToBoxAdapter(
            child: _movieSection('Popular Movies', popular),
          ),
          SliverToBoxAdapter(
            child: _movieSection('Now Playing', latest),
          ),
          SliverToBoxAdapter(
            child: _movieSection('Top Rated', topRated),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 25)),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            subtitle,
            style: const TextStyle(
              color: gold,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroSlider() {
    if (trending.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 390,
      child: PageView.builder(
        controller: _sliderController,
        itemCount: trending.length,
        onPageChanged: (index) {
          setState(() => _slide = index);
        },
        itemBuilder: (context, index) {
          final movie = trending[index];

          return GestureDetector(
            onTap: () => openMovie(movie),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                color: panel,
                image: movie.backdropUrl.isNotEmpty
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(
                          movie.backdropUrl,
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xE6000000),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'TRENDING ON FLIXORA',
                      style: TextStyle(
                        color: goldLight,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      movie.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${movie.year}  •  ⭐ ${movie.rating.toStringAsFixed(1)}',
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => openMovie(movie),
                      icon: const Icon(Icons.info_outline),
                      label: const Text(
                        'Explore Movie',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        trending.length > 8 ? 8 : trending.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _slide % 8 ? 22 : 6,
                          decoration: BoxDecoration(
                            color: i == _slide % 8
                                ? gold
                                : Colors.white54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _movieSection(String title, List<Movie> list) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 23,
                decoration: BoxDecoration(
                  color: gold,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _tab = 1),
                child: const Text(
                  'See All →',
                  style: TextStyle(color: gold),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (context, index) {
              return _movieCard(list[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _movieCard(Movie movie) {
    return GestureDetector(
      onTap: () => openMovie(movie),
      child: Container(
        width: 145,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  movie.posterUrl.isEmpty
                      ? _posterFallback(145, 190)
                      : CachedNetworkImage(
                          imageUrl: movie.posterUrl,
                          height: 190,
                          width: 145,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              _posterFallback(145, 190),
                          errorWidget: (_, __, ___) =>
                              _posterFallback(145, 190),
                        ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => toggleFavourite(movie),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.black87,
                        child: Icon(
                          _favourites.contains(movie.id)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: gold,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '${movie.year}  •  ⭐ ${movie.rating.toStringAsFixed(1)}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterFallback(double width, double height) {
    return Container(
      height: height,
      width: width,
      color: panel,
      child: const Icon(
        Icons.movie_outlined,
        size: 45,
        color: gold,
      ),
    );
  }

  Widget _movieGridSliver(List<Movie> list) {
    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('No movies found')),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _movieCard(list[index]),
          childCount: list.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.64,
          crossAxisSpacing: 4,
          mainAxisSpacing: 10,
        ),
      ),
    );
  }

  List<Movie> _allMovies() {
    final all = <int, Movie>{};

    for (final list in [
      trending,
      popular,
      latest,
      topRated,
    ]) {
      for (final movie in list) {
        all[movie.id] = movie;
      }
    }

    return all.values.toList();
  }

  Widget _allPage() {
    final list = _allMovies();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _searchBox()),
        SliverToBoxAdapter(
          child: _sectionTitle(
            'All Movies',
            '${list.length} MOVIES',
          ),
        ),
        _movieGridSliver(list),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _savedPage() {
    final list = _allMovies()
        .where((movie) => _saved.contains(movie.id))
        .toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(
          child: _sectionTitle(
            'Saved Movies',
            '${list.length} SAVED',
          ),
        ),
        if (list.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(45),
              child: Column(
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 65,
                    color: gold,
                  ),
                  SizedBox(height: 15),
                  Text('No saved movies yet'),
                  SizedBox(height: 6),
                  Text(
                    'Open a movie and tap Save',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          )
        else
          _movieGridSliver(list),
      ],
    );
  }

  Widget _profilePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 2),
            ),
            child: const CircleAvatar(
              radius: 42,
              backgroundColor: panel,
              child: Icon(
                Icons.person,
                size: 48,
                color: gold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Flixora User',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: gold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your cinematic experience',
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 25),
          TextButton.icon(
            onPressed: () => _message('Account feature coming soon'),
            icon: const Icon(Icons.login, color: gold),
            label: const Text(
              'Sign in / Register',
              style: TextStyle(color: gold),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'This product uses the TMDB API but is not endorsed or certified by TMDB.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String error, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 55, color: gold),
            const SizedBox(height: 16),
            const Text(
              'Could not load movies',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: panel,
      ),
    );
  }
}

class NoInternetScreen extends StatefulWidget {
  final Future<bool> Function()? onRetry;
  final bool inline;

  const NoInternetScreen({
    super.key,
    this.onRetry,
    this.inline = false,
  });

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool checking = false;

  Future<void> retry() async {
    setState(() => checking = true);

    bool connected = false;

    try {
      connected = widget.onRetry != null
          ? await widget.onRetry!()
          : await InternetService.isOnline();
    } catch (_) {
      connected = false;
    }

    if (!mounted) return;

    setState(() => checking = false);

    if (connected) {
      if (!widget.inline) {
        Navigator.pop(context, true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Still offline. Please check your connection.',
          ),
          backgroundColor: panel,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: gold,
                  size: 85,
                ),
                const SizedBox(height: 28),
                const Text(
                  'Connect to the internet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'When your internet connection is restored:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Explore various movies, TV series and more',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'HD',
                  style: TextStyle(
                    color: gold,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'All free download with less data but good quality',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 35),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: checking ? null : retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        vertical: 15,
                      ),
                    ),
                    child: checking
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Retry',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      AppSettings.openAppSettings(
                        type: AppSettingsType.wifi,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: gold,
                      side: const BorderSide(color: gold),
                      padding: const EdgeInsets.symmetric(
                        vertical: 15,
                      ),
                    ),
                    child: const Text(
                      'Go to Settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 
class DownloadsScreen extends StatelessWidget {
  final List<DownloadTask> downloads;

  const DownloadsScreen({
    super.key,
    required this.downloads,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text(
          'Downloads',
          style: TextStyle(
            color: gold,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: downloads.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.download_for_offline_outlined,
                      size: 75,
                      color: gold,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'No downloads yet',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Movies you download will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A permitted video source is required.',
                      style: TextStyle(
                        color: goldLight.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: downloads.length,
              itemBuilder: (context, index) {
                final item = downloads[index];

                return Card(
                  color: panel,
                  child: ListTile(
                    leading: item.poster.isEmpty
                        ? const Icon(Icons.movie, color: gold)
                        : CachedNetworkImage(
                            imageUrl: item.poster,
                            width: 48,
                            fit: BoxFit.cover,
                          ),
                    title: Text(item.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: item.progress,
                          color: gold,
                          backgroundColor: Colors.white12,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${(item.progress * 100).toStringAsFixed(0)}% • ${item.status}',
                          style: const TextStyle(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class MovieDetailsScreen extends StatefulWidget {
  final Movie movie;
  final bool isFavourite;
  final bool isSaved;
  final VoidCallback onFavourite;
  final VoidCallback onSave;
  final VoidCallback onDownload;

  const MovieDetailsScreen({
    super.key,
    required this.movie,
    required this.isFavourite,
    required this.isSaved,
    required this.onFavourite,
    required this.onSave,
    required this.onDownload,
  });

  @override
  State<MovieDetailsScreen> createState() =>
      _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  late bool favourite;
  late bool saved;

  Map<String, dynamic>? extraDetails;
  String? detailsError;
  bool detailsLoading = true;

  @override
  void initState() {
    super.initState();

    favourite = widget.isFavourite;
    saved = widget.isSaved;

    loadDetails();
  }

  Future<void> loadDetails() async {
    final online = await InternetService.isOnline();

    if (!mounted) return;

    if (!online) {
      setState(() {
        detailsLoading = false;
        detailsError =
            'Connect to the internet to load movie details.';
      });

      return;
    }

    try {
      final data = await TmdbService.details(widget.movie.id);

      if (!mounted) return;

      setState(() {
        extraDetails = data;
        detailsLoading = false;
        detailsError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        detailsError = e.toString();
        detailsLoading = false;
      });
    }
  }

  void showSourceMessage(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No licensed video source is connected for $action yet.',
        ),
        backgroundColor: panel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;

    final genres = (extraDetails?['genres'] as List? ?? [])
        .map((g) => g['name'].toString())
        .join(' • ');

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: bg,
            iconTheme: const IconThemeData(color: gold),
            flexibleSpace: FlexibleSpaceBar(
              background: movie.backdropUrl.isEmpty
                  ? Container(color: panel)
                  : CachedNetworkImage(
                      imageUrl: movie.backdropUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: panel),
                      errorWidget: (_, __, ___) =>
                          Container(color: panel),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${movie.year}  •  ⭐ ${movie.rating.toStringAsFixed(1)}',
                    style: const TextStyle(color: goldLight),
                  ),
                  const SizedBox(height: 12),
                  if (detailsLoading)
                    const LinearProgressIndicator(color: gold)
                  else if (detailsError == null && genres.isNotEmpty)
                    Text(
                      genres,
                      style: const TextStyle(color: Colors.white54),
                    )
                  else if (detailsError != null)
                    Text(
                      detailsError!,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Overview',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    movie.overview,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.6,
                      fontSize: 15,
                    ),
                  ),
                  if (extraDetails != null) ...[
                    const SizedBox(height: 22),
                    Text(
                      'Runtime: ${extraDetails!['runtime'] ?? 'N/A'} minutes',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Release date: ${movie.releaseDate.isEmpty ? 'N/A' : movie.releaseDate}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                      ),
                      onPressed: () => showSourceMessage('playback'),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(
                        'Watch',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: gold,
                        side: const BorderSide(color: gold),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      onPressed: widget.onDownload,
                      icon: const Icon(Icons.download),
                      label: const Text(
                        'Download',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: gold,
                            side: const BorderSide(color: gold),
                          ),
                          onPressed: () {
                            widget.onFavourite();

                            setState(() {
                              favourite = !favourite;
                            });
                          },
                          icon: Icon(
                            favourite
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                          label: Text(
                            favourite ? 'Liked' : 'Favourite',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: gold,
                            side: const BorderSide(color: gold),
                          ),
                          onPressed: () {
                            widget.onSave();

                            setState(() {
                              saved = !saved;
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  saved
                                      ? 'Added to saved list'
                                      : 'Removed from saved list',
                                ),
                              ),
                            );
                          },
                          icon: Icon(
                            saved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                          label: Text(saved ? 'Saved' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Center(
                    child: Text(
                      'FLIXORA',
                      style: TextStyle(
                        color: gold,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MoviePlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const MoviePlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<MoviePlayerScreen> createState() =>
      _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  late VideoPlayerController controller;

  bool ready = false;
  bool controlsVisible = true;

  double volume = 1;
  double speed = 1;

  Timer? hideTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );

    controller.initialize().then((_) {
      if (!mounted) return;

      setState(() => ready = true);

      controller.play();
      resetHideTimer();
    }).catchError((_) {
      if (mounted) {
        setState(() => ready = false);
      }
    });
  }

  void resetHideTimer() {
    hideTimer?.cancel();

    hideTimer = Timer(
      const Duration(seconds: 4),
      () {
        if (mounted && controller.value.isPlaying) {
          setState(() => controlsVisible = false);
        }
      },
    );
  }

  void toggleControls() {
    setState(() {
      controlsVisible = !controlsVisible;
    });

    if (controlsVisible) {
      resetHideTimer();
    }
  }

  String formatTime(Duration duration) {
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    final hours = duration.inHours;

    return hours > 0
        ? '$hours:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    controller.dispose();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggleControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (ready)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: gold),
              ),
            if (controlsVisible && ready)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Column(
                    children: [
                      SafeArea(
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.arrow_back,
                                color: white,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 38,
                            onPressed: () {
                              final position = controller.value.position;

                              controller.seekTo(
                                position -
                                    const Duration(seconds: 10),
                              );
                            },
                            icon: const Icon(
                              Icons.replay_10,
                              color: white,
                            ),
                          ),
                          const SizedBox(width: 25),
                          IconButton(
                            iconSize: 55,
                            onPressed: () {
                              setState(() {
                                controller.value.isPlaying
                                    ? controller.pause()
                                    : controller.play();
                              });

                              resetHideTimer();
                            },
                            icon: Icon(
                              controller.value.isPlaying
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: gold,
                            ),
                          ),
                          const SizedBox(width: 25),
                          IconButton(
                            iconSize: 38,
                            onPressed: () {
                              final position = controller.value.position;
                              final duration = controller.value.duration;

                              final next = position +
                                  const Duration(seconds: 10);

                              controller.seekTo(
                                next > duration ? duration : next,
                              );
                            },
                            icon: const Icon(
                              Icons.forward_10,
                              color: white,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          18,
                          0,
                          18,
                          15,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  formatTime(controller.value.position),
                                  style: const TextStyle(color: white),
                                ),
                                Expanded(
                                  child: VideoProgressIndicator(
                                    controller,
                                    allowScrubbing: true,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    colors: const VideoProgressColors(
                                      playedColor: gold,
                                      bufferedColor: Colors.white38,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatTime(controller.value.duration),
                                  style: const TextStyle(color: white),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(
                                  Icons.volume_up,
                                  color: white,
                                  size: 19,
                                ),
                                Expanded(
                                  child: Slider(
                                    value: volume,
                                    min: 0,
                                    max: 1,
                                    activeColor: gold,
                                    onChanged: (value) {
                                      setState(() => volume = value);
                                      controller.setVolume(value);
                                    },
                                  ),
                                ),
                                PopupMenuButton<double>(
                                  initialValue: speed,
                                  color: panel,
                                  onSelected: (value) {
                                    setState(() => speed = value);
                                    controller.setPlaybackSpeed(value);
                                  },
                                  itemBuilder: (_) => [
                                    for (final value in [
                                      0.5,
                                      0.75,
                                      1.0,
                                      1.25,
                                      1.5,
                                      2.0,
                                    ])
                                      PopupMenuItem(
                                        value: value,
                                        child: Text('${value}x'),
                                      ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      '${speed}x',
                                      style: const TextStyle(
                                        color: white,
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
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
