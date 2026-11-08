
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient? supabaseClient;

const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
      );
      supabaseClient = Supabase.instance.client;
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
    }
  }

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
  final int sourceId;
  final String source;
  final String title;
  final String year;
  final String overview;
  final String poster;
  final String backdrop;
  final double rating;
  final String releaseDate;
  final List<String> genres;
  final double? runtime;
  final String videoUrl;
  final String downloadUrl;

  const Movie({
    required this.id,
    this.sourceId = 0,
    this.source = 'tmdb',
    required this.title,
    required this.year,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.rating,
    required this.releaseDate,
    this.genres = const [],
    this.runtime,
    this.videoUrl = '',
    this.downloadUrl = '',
  });

  bool get isFlixora => source == 'flixora';

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

  factory Movie.fromSupabase(Map<String, dynamic> json) {
    final dbId = (json['id'] as num?)?.toInt() ?? 0;
    final date = (json['release_date'] ?? '').toString();
    final rawGenres = json['genre'];

    final genreList = rawGenres is List
        ? rawGenres.map((item) => item.toString()).toList()
        : <String>[];

    return Movie(
      id: -dbId.abs(),
      sourceId: dbId,
      source: 'flixora',
      title: (json['title'] ?? 'Unknown Movie').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : 'N/A',
      releaseDate: date,
      overview: (json['description'] ?? 'No description available.').toString(),
      poster: (json['poster_url'] ?? '').toString(),
      backdrop: (json['backdrop_url'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      genres: genreList,
      runtime: (json['runtime'] as num?)?.toDouble(),
      videoUrl: (json['video_url'] ?? '').toString(),
      downloadUrl: (json['download_url'] ?? '').toString(),
    );
  }

  factory Movie.fromCache(Map<String, dynamic> json) {
    return Movie(
      id: (json['id'] as num?)?.toInt() ?? 0,
      sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
      source: (json['source'] ?? 'tmdb').toString(),
      title: (json['title'] ?? 'Unknown Movie').toString(),
      year: (json['year'] ?? 'N/A').toString(),
      overview: (json['overview'] ?? '').toString(),
      poster: (json['poster'] ?? '').toString(),
      backdrop: (json['backdrop'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      releaseDate: (json['releaseDate'] ?? '').toString(),
      genres: (json['genres'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      runtime: (json['runtime'] as num?)?.toDouble(),
      videoUrl: (json['videoUrl'] ?? '').toString(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'source': source,
        'title': title,
        'year': year,
        'overview': overview,
        'poster': poster,
        'backdrop': backdrop,
        'rating': rating,
        'releaseDate': releaseDate,
        'genres': genres,
        'runtime': runtime,
        'videoUrl': videoUrl,
        'downloadUrl': downloadUrl,
      };

  bool _isFullUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  String get posterUrl {
    if (poster.isEmpty) return '';
    if (_isFullUrl(poster)) return poster;
    return '${imageBase}w500$poster';
  }

  String get backdropUrl {
    if (backdrop.isEmpty) return posterUrl;
    if (_isFullUrl(backdrop)) return backdrop;
    return '${imageBase}w1280$backdrop';
  }
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

      return response.statusCode == 204 || response.statusCode == 200;
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
  static const String flixoraKey = 'flixora_published';
  static const String favouritesKey = 'flixora_favourites';
  static const String savedKey = 'flixora_saved';

  static Future<void> saveList(String key, List<Movie> movies) async {
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

  static Future<void> saveSearch(String query, List<Movie> movies) async {
    final key = 'flixora_search_${query.trim().toLowerCase()}';
    await saveList(key, movies);
  }

  static Future<List<Movie>> getSearch(String query) async {
    final key = 'flixora_search_${query.trim().toLowerCase()}';
    return getList(key);
  }

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
      throw Exception('Movie service is not configured.');
    }

    final uri = Uri.parse('$base/$endpoint').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': 'en-US',
        'page': '1',
      },
    );

    final response = await http.get(uri).timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200) {
      throw Exception('Could not load movies.');
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
      throw Exception('Movie service is not configured.');
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

    final response = await http.get(uri).timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200) {
      throw Exception('Search failed.');
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
      throw Exception('Movie service is not configured.');
    }

    final uri = Uri.parse('$base/movie/$id').replace(
      queryParameters: {
        'api_key': apiKey,
        'language': 'en-US',
      },
    );

    final response = await http.get(uri).timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200) {
      throw Exception('Could not load movie details.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class FlixoraMovieService {
  static Future<List<Movie>> getPublishedMovies() async {
    final client = supabaseClient;
    if (client == null) return [];

    try {
      final response = await client
          .from('movies')
          .select()
          .eq('is_published', true)
          .order('created_at', ascending: false);

      return (response as List)
          .whereType<Map>()
          .map(
            (row) => Movie.fromSupabase(
              Map<String, dynamic>.from(row),
            ),
          )
          .where((movie) => movie.sourceId > 0)
          .toList();
    } catch (e) {
      debugPrint('Could not load published movies: $e');
      return [];
    }
  }

  static Future<List<Movie>> searchPublishedMovies(String query) async {
    final client = supabaseClient;
    if (client == null || query.trim().isEmpty) return [];

    try {
      final response = await client
          .from('movies')
          .select()
          .eq('is_published', true)
          .ilike('title', '%${query.trim()}%')
          .order('created_at', ascending: false);

      return (response as List)
          .whereType<Map>()
          .map(
            (row) => Movie.fromSupabase(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Movie search failed: $e');
      return [];
    }
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
          if (total > 0) onProgress(received / total);
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

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

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
  List<Movie> flixoraMovies = [];
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
        if (_allMovies().isEmpty) homeError = 'offline';
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
      MovieCache.getList(MovieCache.flixoraKey),
    ]);

    if (!mounted) return;

    setState(() {
      trending = results[0];
      popular = results[1];
      latest = results[2];
      topRated = results[3];
      flixoraMovies = results[4];
      loading = false;
      homeError = null;
    });
  }

  void _listenToConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(
      (results) async {
        final hasNetwork = !results.contains(ConnectivityResult.none);

        if (!hasNetwork) {
          if (!mounted) return;

          setState(() {
            _online = false;
            _connectionKnown = true;
            if (_allMovies().isEmpty) homeError = 'offline';
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
          if (_allMovies().isEmpty) homeError = 'offline';
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
        FlixoraMovieService.getPublishedMovies(),
      ]);

      if (!mounted) return;

      setState(() {
        trending = results[0];
        popular = results[1];
        latest = results[2];
        topRated = results[3];
        flixoraMovies = results[4];
        loading = false;
        homeError = null;
      });

      await Future.wait([
        MovieCache.saveList(MovieCache.trendingKey, trending),
        MovieCache.saveList(MovieCache.popularKey, popular),
        MovieCache.saveList(MovieCache.latestKey, latest),
        MovieCache.saveList(MovieCache.topRatedKey, topRated),
        MovieCache.saveList(MovieCache.flixoraKey, flixoraMovies),
      ]);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        if (_allMovies().isEmpty) homeError = e.toString();
      });
    } finally {
      _refreshing = false;
    }
  }

  List<Movie> _allMovies() {
    final combined = <Movie>[
      ...flixoraMovies,
      ...trending,
      ...popular,
      ...latest,
      ...topRated,
    ];

    final seen = <int>{};
    return combined.where((movie) => seen.add(movie.id)).toList();
  }

  Future<void> searchMovies(String query) async {
    final text = query.trim();

    if (text.isEmpty) {
      if (!mounted) return;

      setState(() {
        _search = '';
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _search = text;
      _searchLoading = true;
      _searchError = null;
    });

    final results = await Future.wait([
      TmdbService.search(text).catchError((_) => <Movie>[]),
      FlixoraMovieService.searchPublishedMovies(text)
          .catchError((_) => <Movie>[]),
    ]);

    if (!mounted || _search.trim().toLowerCase() != text.toLowerCase()) {
      return;
    }

    final combined = <Movie>[
      ...results[1],
      ...results[0],
    ];

    final seen = <int>{};
    final unique = combined.where((movie) => seen.add(movie.id)).toList();

    setState(() {
      searchResults = unique;
      _searchLoading = false;
      _searchError = unique.isEmpty ? 'No movies found.' : null;
    });

    await MovieCache.saveSearch(text, unique);
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _search = '';
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }

    _searchTimer = Timer(
      const Duration(milliseconds: 500),
      () => searchMovies(value),
    );
  }

  Future<void> _toggleFavourite(Movie movie) async {
    setState(() {
      if (_favourites.contains(movie.id)) {
        _favourites.remove(movie.id);
      } else {
        _favourites.add(movie.id);
      }
    });

    await MovieCache.saveFavourites(_favourites);
  }

  Future<void> _toggleSaved(Movie movie) async {
    setState(() {
      if (_saved.contains(movie.id)) {
        _saved.remove(movie.id);
      } else {
        _saved.add(movie.id);
      }
    });

    await MovieCache.saveSaved(_saved);
  }

  Future<void> addDownload(Movie movie) async {
    if (movie.downloadUrl.trim().isEmpty) {
      _showMessage('Download is not available for this movie.');
      return;
    }

    if (_downloads.any(
      (task) =>
          task.movieId == movie.id &&
          (task.status == 'Downloading' || task.status == 'Completed'),
    )) {
      _showMessage('This movie is already downloading or downloaded.');
      return;
    }

    final task = DownloadTask(
      movieId: movie.id,
      title: movie.title,
      poster: movie.posterUrl,
      status: 'Downloading',
    );

    setState(() => _downloads.insert(0, task));

    await DownloadManager.download(
      url: movie.downloadUrl,
      fileName: '${movie.id}_${movie.title}',
      onProgress: (value) {
        if (!mounted) return;
        setState(() {
          task.progress = value;
          task.status = 'Downloading';
        });
      },
      onComplete: (path) {
        if (!mounted) return;
        setState(() {
          task.progress = 1;
          task.status = 'Completed';
          task.filePath = path;
        });
        _showMessage('Download completed: ${movie.title}');
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => task.status = 'Failed');
        _showMessage(message);
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: panel,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openMovie(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsScreen(
          movie: movie,
          isFavourite: _favourites.contains(movie.id),
          isSaved: _saved.contains(movie.id),
          onFavourite: () => _toggleFavourite(movie),
          onSave: () => _toggleSaved(movie),
          onDownload: () => addDownload(movie),
        ),
      ),
    );
  }

  List<Movie> _moviesForIds(Set<int> ids) {
    final all = _allMovies();
    return all.where((movie) => ids.contains(movie.id)).toList();
  }

  Widget _poster(Movie movie, {double width = 125}) {
    return GestureDetector(
      onTap: () => _openMovie(movie),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: movie.posterUrl.isEmpty
                    ? _posterPlaceholder()
                    : CachedNetworkImage(
                        imageUrl: movie.posterUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _posterPlaceholder(),
                        errorWidget: (_, __, ___) => _posterPlaceholder(),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              movie.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              movie.year,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      color: panel,
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_outlined,
        color: gold,
        size: 35,
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String? subtitle,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(color: gold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _movieRow(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox(height: 5);

    return SizedBox(
      height: 225,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        scrollDirection: Axis.horizontal,
        itemCount: movies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 13),
        itemBuilder: (_, index) => _poster(movies[index]),
      ),
    );
  }

  Widget _featuredSlider() {
    if (trending.isEmpty) return const SizedBox.shrink();

    final slides = trending.take(5).toList();

    return SizedBox(
      height: 420,
      child: Stack(
        children: [
          PageView.builder(
            controller: _sliderController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _slide = index);
            },
            itemBuilder: (_, index) {
              final movie = slides[index];

              return GestureDetector(
                onTap: () => _openMovie(movie),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    movie.backdropUrl.isEmpty
                        ? _posterPlaceholder()
                        : CachedNetworkImage(
                            imageUrl: movie.backdropUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _posterPlaceholder(),
                            errorWidget: (_, __, ___) => _posterPlaceholder(),
                          ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Color(0x33000000),
                            bg,
                          ],
                          stops: [0.05, 0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 35,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FEATURED',
                            style: TextStyle(
                              color: gold,
                              fontSize: 12,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            movie.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 27,
                              color: white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(Icons.star, color: gold, size: 16),
                              const SizedBox(width: 5),
                              Text(
                                movie.rating.toStringAsFixed(1),
                                style: const TextStyle(color: white),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                movie.year,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => _openMovie(movie),
                            icon: const Icon(Icons.info_outline),
                            label: const Text('View Details'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            top: 15,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'FLIXORA',
                style: TextStyle(
                  color: goldLight,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 15,
            right: 20,
            child: Row(
              children: List.generate(
                slides.length,
                (index) => Container(
                  margin: const EdgeInsets.only(left: 5),
                  width: _slide == index ? 19 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _slide == index ? gold : Colors.white54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeContent() {
    return RefreshIndicator(
      color: gold,
      backgroundColor: panel,
      onRefresh: loadHome,
      child: ListView(
        children: [
          _featuredSlider(),
          if (flixoraMovies.isNotEmpty) ...[
            _sectionTitle(
              'Flixora Originals',
              subtitle: 'Movies published by Flixora',
            ),
            _movieRow(flixoraMovies),
          ],
          _sectionTitle('Trending This Week'),
          _movieRow(trending),
          _sectionTitle('Popular Movies'),
          _movieRow(popular),
          _sectionTitle('Now Playing'),
          _movieRow(latest),
          _sectionTitle('Top Rated'),
          _movieRow(topRated),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _searchContent() {
    if (_searchLoading) {
      return const Center(
        child: CircularProgressIndicator(color: gold),
      );
    }

    if (searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search, size: 55, color: Colors.white30),
              const SizedBox(height: 12),
              Text(
                _searchError ?? 'Search movies by title',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.53,
        crossAxisSpacing: 12,
        mainAxisSpacing: 15,
      ),
      itemCount: searchResults.length,
      itemBuilder: (_, index) => _poster(
        searchResults[index],
        width: double.infinity,
      ),
    );
  }

  Widget _collectionContent(String title, List<Movie> movies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            title,
            style: const TextStyle(
              color: white,
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: movies.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing here yet.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.53,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 15,
                  ),
                  itemCount: movies.length,
                  itemBuilder: (_, index) => _poster(
                    movies[index],
                    width: double.infinity,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _downloadsContent() => DownloadsScreen(tasks: _downloads);

  Widget _profileContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.13),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                color: gold,
                size: 48,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'FLIXORA',
              style: TextStyle(
                color: gold,
                fontSize: 25,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your movie destination',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 30),
            _profileTile(
              Icons.favorite_outline,
              'My Favourites',
              () => setState(() => _tab = 3),
            ),
            _profileTile(
              Icons.bookmark_outline,
              'Saved Movies',
              () => setState(() => _tab = 4),
            ),
            _profileTile(
              Icons.download_outlined,
              'Downloads',
              () => setState(() => _tab = 5),
            ),
            _profileTile(Icons.refresh, 'Refresh Movies', loadHome),
            const SizedBox(height: 25),
            const Text(
              'Flixora — Movies, made simple.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileTile(
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return Card(
      color: panel,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: gold),
        title: Text(title, style: const TextStyle(color: white)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }

  Widget _currentPage() {
    if (_search.isNotEmpty) return _searchContent();

    switch (_tab) {
      case 0:
        if (loading && _allMovies().isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (homeError != null && _allMovies().isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: gold, size: 45),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load movies.',
                  style: TextStyle(color: white),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: loadHome,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          );
        }

        if (_allMovies().isEmpty) {
          return const Center(
            child: Text(
              'No movies available yet.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return _homeContent();

      case 1:
        return _collectionContent('All Movies', _allMovies());
      case 2:
        return _collectionContent('Flixora Originals', flixoraMovies);
      case 3:
        return _collectionContent(
          'My Favourites',
          _moviesForIds(_favourites),
        );
      case 4:
        return _collectionContent(
          'Saved Movies',
          _moviesForIds(_saved),
        );
      case 5:
        return _downloadsContent();
      case 6:
        return _profileContent();
      default:
        return _homeContent();
    }
  }

  String _pageTitle() {
    if (_search.isNotEmpty) return 'Search Results';

    switch (_tab) {
      case 0:
        return 'FLIXORA';
      case 1:
        return 'All Movies';
      case 2:
        return 'Flixora Originals';
      case 3:
        return 'Favourites';
      case 4:
        return 'Saved';
      case 5:
        return 'Downloads';
      case 6:
        return 'Profile';
      default:
        return 'FLIXORA';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitle(),
          style: const TextStyle(
            color: gold,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          if (_tab == 0 || _tab == 1 || _tab == 2)
            IconButton(
              onPressed: () {
                setState(() {
                  _tab = 0;
                  _search = '';
                  _searchController.clear();
                });
                FocusScope.of(context).unfocus();
              },
              icon: const Icon(Icons.home_outlined),
            ),
          if (_connectionKnown)
            Padding(
              padding: const EdgeInsets.only(right: 15),
              child: Icon(
                _online ? Icons.wifi : Icons.wifi_off,
                color: _online ? Colors.green : Colors.redAccent,
                size: 19,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 5, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: white),
              decoration: InputDecoration(
                hintText: 'Search movies...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: gold),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          FocusScope.of(context).unfocus();
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white54,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: panel,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _currentPage()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          FocusScope.of(context).unfocus();
          _searchController.clear();

          setState(() {
            _search = '';
            searchResults = [];
            _searchError = null;
            _searchLoading = false;
            _tab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'Movies',
          ),
          NavigationDestination(
            icon: Icon(Icons.stars_outlined),
            selectedIcon: Icon(Icons.stars),
            label: 'Originals',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Likes',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class NoInternetScreen extends StatelessWidget {
  const NoInternetScreen({super.key});

  Future<void> _openWifiSettings(BuildContext context) async {
    try {
      await AppSettings.openAppSettings(
        type: AppSettingsType.wifi,
      );
    } catch (_) {
      try {
        await AppSettings.openAppSettings();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to open settings.'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 75,
                color: gold,
              ),
              const SizedBox(height: 20),
              const Text(
                'No Internet Connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 25),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _openWifiSettings(context),
                icon: const Icon(Icons.settings),
                label: const Text('Open Wi-Fi Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// DOWNLOADS SCREEN
// --------------------------------------------------

class DownloadsScreen extends StatelessWidget {
  final List<DownloadTask> tasks;

  const DownloadsScreen({
    super.key,
    required this.tasks,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.download_outlined,
                size: 65,
                color: Colors.white30,
              ),
              const SizedBox(height: 15),
              const Text(
                'No Downloads Yet',
                style: TextStyle(
                  color: white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your downloaded movies will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 65,
                  height: 90,
                  child: task.poster.isEmpty
                      ? Container(
                          color: bg,
                          child: const Icon(
                            Icons.movie,
                            color: gold,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: task.poster,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: bg,
                            child: const Icon(
                              Icons.movie,
                              color: gold,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      task.status,
                      style: TextStyle(
                        color: task.status == 'Completed'
                            ? Colors.greenAccent
                            : task.status == 'Failed'
                                ? Colors.redAccent
                                : gold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: task.progress.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.white12,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(gold),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${(task.progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    if (task.status == 'Completed' &&
                        task.filePath != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                          'Saved on this device',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------
// MOVIE DETAILS SCREEN
// --------------------------------------------------

class MovieDetailsScreen extends StatelessWidget {
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

  Widget _detailItem(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: gold),
        const SizedBox(width: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final runtime = movie.runtime ?? 0;

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: bg,
            foregroundColor: white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  movie.backdropUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: movie.backdropUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: panel),
                        )
                      : Container(color: panel),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          bg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    style: const TextStyle(
                      color: white,
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 15,
                    runSpacing: 10,
                    children: [
                      _detailItem(
                        Icons.star,
                        movie.rating.toStringAsFixed(1),
                      ),
                      _detailItem(
                        Icons.calendar_today,
                        movie.year,
                      ),
                      if (runtime > 0)
                        _detailItem(
                          Icons.schedule,
                          '${runtime.toStringAsFixed(0)} min',
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                          onPressed: movie.videoUrl.isNotEmpty
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MoviePlayerScreen(
                                        movie: movie,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text(
                            'Watch Now',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: panel,
                          foregroundColor:
                              isFavourite ? Colors.redAccent : white,
                        ),
                        onPressed: onFavourite,
                        icon: Icon(
                          isFavourite
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                      ),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: panel,
                          foregroundColor: isSaved ? gold : white,
                        ),
                        onPressed: onSave,
                        icon: Icon(
                          isSaved
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (movie.downloadUrl.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: gold,
                          side: const BorderSide(color: gold),
                          padding: const EdgeInsets.symmetric(
                            vertical: 13,
                          ),
                        ),
                        onPressed: onDownload,
                        icon: const Icon(Icons.download),
                        label: const Text('Download Movie'),
                      ),
                    ),
                  const SizedBox(height: 25),
                  const Text(
                    'Overview',
                    style: TextStyle(
                      color: white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    movie.overview.isEmpty
                        ? 'No description available.'
                        : movie.overview,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.7,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 25),
                  if (movie.genres.isNotEmpty) ...[
                    const Text(
                      'Genres',
                      style: TextStyle(
                        color: white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: movie.genres.map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: gold.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            genre,
                            style: const TextStyle(
                              color: gold,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// MOVIE PLAYER SCREEN
// --------------------------------------------------

class MoviePlayerScreen extends StatefulWidget {
  final Movie movie;

  const MoviePlayerScreen({
    super.key,
    required this.movie,
  });

  @override
  State<MoviePlayerScreen> createState() =>
      _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  VideoPlayerController? _controller;

  bool _initializing = true;
  String? _error;
  bool _showControls = true;

  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final videoUrl = widget.movie.videoUrl.trim();

    if (videoUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Video is not available.';
      });
      return;
    }

    VideoPlayerController? controller;

    try {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
      );

      _controller = controller;

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      controller.addListener(_playerListener);

      await controller.setLooping(false);
      await controller.play();

      if (!mounted) return;

      setState(() {
        _initializing = false;
        _error = null;
      });

      _startControlsTimer();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _initializing = false;
        _error = 'Unable to play this video. Please try again.';
      });

      if (controller != null) {
        await controller.dispose();
        if (identical(_controller, controller)) {
          _controller = null;
        }
      }

      debugPrint('Video player error: $e');
    }
  }

  void _playerListener() {
    if (!mounted) return;

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.hasError) {
      setState(() {
        _error =
            controller.value.errorDescription ?? 'Video playback error.';
      });
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();

    _controlsTimer = Timer(
      const Duration(seconds: 4),
      () {
        if (!mounted) return;
        setState(() => _showControls = false);
      },
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);

    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (!mounted) return;

    setState(() {});
    _startControlsTimer();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();

    final controller = _controller;

    if (controller != null) {
      controller.removeListener(_playerListener);
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: white,
        title: Text(
          widget.movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: _initializing
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: gold),
                  SizedBox(height: 15),
                  Text(
                    'Loading video...',
                    style: TextStyle(color: white),
                  ),
                ],
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: gold,
                          size: 55,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: white),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _initializing = true;
                              _error = null;
                            });
                            _initializePlayer();
                          },
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  )
                : controller == null ||
                        !controller.value.isInitialized
                    ? const Text(
                        'Video unavailable.',
                        style: TextStyle(color: white),
                      )
                    : AspectRatio(
                        aspectRatio: controller.value.aspectRatio > 0
                            ? controller.value.aspectRatio
                            : 16 / 9,
                        child: GestureDetector(
                          onTap: _toggleControls,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(controller),
                              if (_showControls)
                                Container(
                                  color: Colors.black26,
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Spacer(),
                                      IconButton(
                                        onPressed: _togglePlay,
                                        iconSize: 65,
                                        color: white,
                                        icon: Icon(
                                          controller.value.isPlaying
                                              ? Icons.pause_circle
                                              : Icons.play_circle,
                                        ),
                                      ),
                                      const Spacer(),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Column(
                                          children: [
                                            VideoProgressIndicator(
                                              controller,
                                              allowScrubbing: true,
                                              colors:
                                                  const VideoProgressColors(
                                                playedColor: gold,
                                                bufferedColor:
                                                    Colors.white54,
                                                backgroundColor:
                                                    Colors.white24,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  _formatDuration(
                                                    controller.value.position,
                                                  ),
                                                  style: const TextStyle(
                                                    color: white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Text(
                                                  _formatDuration(
                                                    controller.value.duration,
                                                  ),
                                                  style: const TextStyle(
                                                    color: white,
                                                    fontSize: 12,
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
                            ],
                          ),
                        ),
                      ),
      ),
    );
  }
}
