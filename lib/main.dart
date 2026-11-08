import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

SupabaseClient? supabaseClient;

const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

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

int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class Movie {
  final int id;
  final int tmdbId;
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
    this.tmdbId = 0,
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
    final movieId = _toInt(json['id']);

    return Movie(
      id: movieId,
      tmdbId: movieId,
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
    final dbId = _toInt(json['id']);
    final tmdbId = _toInt(json['tmdb_id']);
    final date = (json['release_date'] ?? '').toString();
    final rawGenres = json['genre'];

    final genreList = rawGenres is List
        ? rawGenres.map((item) => item.toString()).toList()
        : <String>[];

    return Movie(
      id: -dbId.abs(),
      sourceId: dbId,
      tmdbId: tmdbId,
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
    final cachedId = _toInt(json['id']);
    final cachedSource = (json['source'] ?? 'tmdb').toString();
    final cachedTmdbId = _toInt(json['tmdbId']);

    return Movie(
      id: cachedId,
      tmdbId: cachedTmdbId > 0
          ? cachedTmdbId
          : (cachedSource == 'tmdb' ? cachedId : 0),
      sourceId: _toInt(json['sourceId']),
      source: cachedSource,
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
        'tmdbId': tmdbId,
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

/// Displays network images online, but reads disk cache only while offline.
/// A cache miss offline never starts a network request.
class FlixoraCachedImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final bool isOnline;
  final Widget? placeholder;
  final Widget? fallback;

  const FlixoraCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    required this.isOnline,
    this.placeholder,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final empty = fallback ?? Container(color: panel);
    if (imageUrl.isEmpty) return empty;
    if (isOnline) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        placeholder: (_, __) => placeholder ?? Container(color: panel),
        errorWidget: (_, __, ___) => empty,
      );
    }

    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(imageUrl),
      builder: (context, snapshot) {
        final file = snapshot.data?.file;
        if (file != null && file.existsSync()) {
          return Image.file(file, fit: fit);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder ?? Container(color: panel);
        }
        return empty;
      },
    );
  }
}

class InternetService {
  static Future<bool> isOnline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;

      // Test real Internet reachability, not just Wi-Fi/mobile connectivity.
      final endpoints = <Uri>[
        Uri.parse('https://www.google.com/generate_204'),
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ];

      for (final endpoint in endpoints) {
        try {
          final response = await http
              .get(endpoint)
              .timeout(const Duration(seconds: 4));
          if (response.statusCode == 204 || response.statusCode == 200) {
            return true;
          }
        } catch (_) {
          // Try the fallback endpoint.
        }
      }
      return false;
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
  static const String downloadsKey = 'flixora_downloads';

  static Future<void> saveDownloads(List<DownloadTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        downloadsKey,
        jsonEncode(tasks.where((task) => task.status == 'Completed' && task.filePath != null).map((task) => task.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<List<DownloadTask>> getDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(downloadsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      final tasks = decoded
          .whereType<Map>()
          .map(
            (item) => DownloadTask.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      final valid = <DownloadTask>[];
      for (final task in tasks) {
        if (task.status == 'Completed' &&
            task.filePath != null &&
            await File(task.filePath!).exists()) {
          valid.add(task);
        }
      }
      // Remove stale records whose local video file no longer exists.
      await prefs.setString(
        downloadsKey,
        jsonEncode(valid.map((task) => task.toJson()).toList()),
      );
      return valid;
    } catch (_) {
      return [];
    }
  }

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

    final data = jsonDecode(response.body) as Map<String, dynamic>;
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

    final data = jsonDecode(response.body) as Map<String, dynamic>;
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
  final String videoUrl;
  double progress;
  String status;
  String? filePath;

  DownloadTask({
    required this.movieId,
    required this.title,
    required this.poster,
    this.videoUrl = '',
    this.progress = 0,
    this.status = 'Waiting',
    this.filePath,
  });

  Map<String, dynamic> toJson() => {
        'movieId': movieId,
        'title': title,
        'poster': poster,
        'videoUrl': videoUrl,
        'progress': progress,
        'status': status,
        'filePath': filePath,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        movieId: _toInt(json['movieId']),
        title: (json['title'] ?? 'Downloaded Movie').toString(),
        poster: (json['poster'] ?? '').toString(),
        videoUrl: (json['videoUrl'] ?? '').toString(),
        progress: (json['progress'] as num?)?.toDouble() ?? 1,
        status: (json['status'] ?? 'Completed').toString(),
        filePath: json['filePath']?.toString(),
      );
}

class DownloadManager {
  static final Dio _dio = Dio();

  static Future<void> download({
    required String url,
    required String fileName,
    required int uniqueId,
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty) {
        onError('Invalid download URL.');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();

      final safeName = fileName.replaceAll(
        RegExp(r'[^a-zA-Z0-9_-]'),
        '_',
      );

      final path = '${directory.path}/${safeName}_$uniqueId.mp4';

      await _dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final PageController _sliderController = PageController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _timer;
  Timer? _networkTimer;
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
  bool _checkingConnection = false;

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

  Set<int> get _flixoraTmdbIds {
    return flixoraMovies
        .map((movie) => movie.tmdbId)
        .where((id) => id > 0)
        .toSet();
  }

  List<Movie> _withoutFlixoraDuplicates(List<Movie> movies) {
    final adminIds = _flixoraTmdbIds;

    return movies.where((movie) {
      if (movie.tmdbId <= 0) return true;
      return !adminIds.contains(movie.tmdbId);
    }).toList();
  }

  List<Movie> _deduplicateMovies(List<Movie> movies) {
    final seenTmdbIds = <int>{};
    final seenFallbackIds = <String>{};

    return movies.where((movie) {
      if (movie.tmdbId > 0) {
        return seenTmdbIds.add(movie.tmdbId);
      }

      final fallbackKey = '${movie.source}:${movie.id}';
      return seenFallbackIds.add(fallbackKey);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializeApp();
    _listenToConnectivity();
    _networkTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _refreshConnectionStatus(),
    );

    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted || _tab != 0) return;

        final slideCount = _withoutFlixoraDuplicates(trending).length;
        final visibleCount = slideCount < 5 ? slideCount : 5;

        if (visibleCount == 0) return;

        _slide = (_slide + 1) % visibleCount;

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
    final savedDownloads = await MovieCache.getDownloads();
    if (mounted) {
      setState(() {
        _downloads
          ..clear()
          ..addAll(savedDownloads);
      });
    }

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
    final results = await Future.wait<Set<int>>([
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
    final results = await Future.wait<List<Movie>>([
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshConnectionStatus();
    }
  }

  Future<void> _refreshConnectionStatus() async {
    if (!mounted || _checkingConnection) return;
    _checkingConnection = true;
    try {
      final online = await InternetService.isOnline();
      if (!mounted || online == _online) return;

      final wasOffline = !_online;
      setState(() {
        _online = online;
        _connectionKnown = true;
        if (!online && _allMovies().isEmpty) homeError = 'offline';
      });

      if (online && wasOffline) {
        await loadHome();
        if (_search.trim().isNotEmpty) {
          searchMovies(_search);
        }
      }
    } finally {
      _checkingConnection = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _networkTimer?.cancel();
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
          _connectionKnown = true;
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

      final results = await Future.wait<List<Movie>>([
        TmdbService.getMovies('trending/movie/week')
            .catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/popular')
            .catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/now_playing')
            .catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/top_rated')
            .catchError((_) => <Movie>[]),
        FlixoraMovieService.getPublishedMovies()
            .catchError((_) => <Movie>[]),
      ]);

      if (!mounted) return;

      setState(() {
        trending = results[0];
        popular = results[1];
        latest = results[2];
        topRated = results[3];
        flixoraMovies = results[4];
        loading = false;

        if (_allMovies().isEmpty) {
          homeError = 'Unable to load movies.';
        } else {
          homeError = null;
        }

        final slideCount =
            _withoutFlixoraDuplicates(trending).length;
        final visibleCount = slideCount < 5 ? slideCount : 5;

        if (visibleCount == 0) {
          _slide = 0;
        } else if (_slide >= visibleCount) {
          _slide = 0;
        }
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

    return _deduplicateMovies(combined);
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

    final onlineNow = _online && await InternetService.isOnline();
    if (!mounted) return;
    if (!onlineNow) {
      setState(() {
        _online = false;
        _connectionKnown = true;
      });
      final cached = await MovieCache.getSearch(text);
      if (!mounted) return;
      setState(() {
        _search = text;
        searchResults = cached;
        _searchLoading = false;
        _searchError = cached.isEmpty ? 'Check your internet connection' : null;
      });
      return;
    }

    setState(() {
      _online = true;
      _search = text;
      _searchLoading = true;
      _searchError = null;
    });

    final results = await Future.wait<List<Movie>>([
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

    final unique = _deduplicateMovies(combined);

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
    if (!_online || !await InternetService.isOnline()) {
      if (mounted) {
        setState(() { _online = false; _connectionKnown = true; });
        _showMessage('Check your internet connection');
      }
      return;
    }

    if (movie.downloadUrl.trim().isEmpty) {
      _showMessage('Download is not available for this movie.');
      return;
    }

    final existing = _downloads.where((item) => item.movieId == movie.id).toList();
    if (existing.any((item) => item.status == 'Downloading' || item.status == 'Completed')) {
      _showMessage(existing.any((item) => item.status == 'Completed')
          ? 'This movie is already downloaded.'
          : 'This movie is already downloading.');
      return;
    }

    final task = DownloadTask(
      movieId: movie.id,
      title: movie.title,
      poster: movie.posterUrl,
      videoUrl: movie.videoUrl,
      status: 'Downloading',
    );

    setState(() => _downloads.insert(0, task));

    await DownloadManager.download(
      url: movie.downloadUrl,
      fileName: movie.title,
      uniqueId: movie.id,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => task.progress = progress);
      },
      onComplete: (path) {
        if (!mounted) return;
        setState(() {
          task
            ..progress = 1
            ..status = 'Completed'
            ..filePath = path;
        });
        MovieCache.saveDownloads(_downloads);
        _showMessage('${movie.title} downloaded successfully.');
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _downloads.remove(task));
        _showMessage(message);
      },
    );
  }

  Future<void> _deleteDownload(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Delete Download?', style: TextStyle(color: white)),
        content: const Text('Are you sure you want to delete this movie?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (task.filePath != null) {
      try {
        final file = File(task.filePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        _showMessage('Could not delete downloaded file.');
        return;
      }
    }
    if (!mounted) return;
    setState(() => _downloads.remove(task));
    await MovieCache.saveDownloads(_downloads);
    _showMessage('Download removed from this device.');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: panel,
        ),
      );
  }

  List<Movie> _moviesForIds(Set<int> ids) {
    return _allMovies()
        .where((movie) => ids.contains(movie.id))
        .toList();
  }

  void _openMovie(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsScreen(
          movie: movie,
          isOnline: _online,
          isFavourite: _favourites.contains(movie.id),
          isSaved: _saved.contains(movie.id),
          onFavourite: () => _toggleFavourite(movie),
          onSave: () => _toggleSaved(movie),
          onDownload: () => addDownload(movie),
          onWatch: () async {
            DownloadTask? downloaded;
            for (final task in _downloads) {
              if (task.movieId == movie.id && task.status == 'Completed' &&
                  task.filePath != null && File(task.filePath!).existsSync()) {
                downloaded = task;
                break;
              }
            }
            if (downloaded != null) {
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => MoviePlayerScreen(
                  movie: movie,
                  localFilePath: downloaded!.filePath,
                ),
              ));
              return;
            }
            if (!_online || !await InternetService.isOnline()) {
              if (mounted) {
                setState(() { _online = false; _connectionKnown = true; });
                _showMessage('Check your internet connection');
              }
              return;
            }
            if (!mounted) return;
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => MoviePlayerScreen(movie: movie),
            ));
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
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
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _movieRow(List<Movie> movies) {
    if (movies.isEmpty) {
      return const SizedBox(height: 8);
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];

          return GestureDetector(
            onTap: () => _openMovie(movie),
            child: Container(
              width: 125,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: double.infinity,
                        child: movie.posterUrl.isEmpty
                            ? Container(
                                color: panel,
                                child: const Icon(
                                  Icons.movie,
                                  color: gold,
                                  size: 35,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: movie.posterUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: panel,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: gold,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: panel,
                                  child: const Icon(
                                    Icons.movie,
                                    color: gold,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star, color: gold, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        movie.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        movie.year,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _featuredSlider() {
    final slides = _withoutFlixoraDuplicates(trending).take(5).toList();

    if (slides.isEmpty) {
      return const SizedBox(height: 12);
    }

    return SizedBox(
      height: 390,
      child: Stack(
        children: [
          PageView.builder(
            controller: _sliderController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _slide = index);
            },
            itemBuilder: (context, index) {
              final movie = slides[index];

              return Stack(
                fit: StackFit.expand,
                children: [
                  movie.backdropUrl.isEmpty
                      ? Container(color: panel)
                      : CachedNetworkImage(
                          imageUrl: movie.backdropUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: panel,
                          ),
                        ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xDD080808),
                          bg,
                        ],
                        stops: [0.1, 0.65, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 38,
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
                            const Icon(
                              Icons.star,
                              color: gold,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              movie.rating.toStringAsFixed(1),
                              style: const TextStyle(color: white),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              movie.year,
                              style: const TextStyle(
                                color: Colors.white70,
                              ),
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
          _movieRow(_withoutFlixoraDuplicates(trending)),
          _sectionTitle('Popular Movies'),
          _movieRow(_withoutFlixoraDuplicates(popular)),
          _sectionTitle('Now Playing'),
          _movieRow(_withoutFlixoraDuplicates(latest)),
          _sectionTitle('Top Rated'),
          _movieRow(_withoutFlixoraDuplicates(topRated)),
          const SizedBox(height: 25),
        ],
      ),
    );
  }

  Widget _collectionContent(String title, List<Movie> movies) {
    if (movies.isEmpty) {
      return Center(
        child: Text(
          'No $title available.',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.53,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];

        return GestureDetector(
          onTap: () => _openMovie(movie),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: double.infinity,
                    child: movie.posterUrl.isEmpty
                        ? Container(
                            color: panel,
                            child: const Icon(
                              Icons.movie,
                              color: gold,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: panel,
                              child: const Icon(
                                Icons.movie,
                                color: gold,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                movie.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              Text(
                movie.year,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
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
        child: Text(
          _searchError ?? 'Search for a movie.',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    return _collectionContent('Search Results', searchResults);
  }

  Widget _downloadsContent() {
    return DownloadsScreen(
      tasks: _downloads,
      onDelete: _deleteDownload,
      onPlay: (task) {
        if (task.filePath == null) return;
        final movie = Movie(
          id: task.movieId,
          title: task.title,
          year: 'N/A',
          overview: '',
          poster: task.poster,
          backdrop: task.poster,
          rating: 0,
          releaseDate: '',
          videoUrl: task.filePath!,
        );
        Navigator.push(context, MaterialPageRoute(builder: (_) => MoviePlayerScreen(movie: movie, localFilePath: task.filePath)));
      },
    );
  }

  Widget _profileContent() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 15),
        const CircleAvatar(
          radius: 42,
          backgroundColor: panel,
          child: Icon(
            Icons.movie_creation_outlined,
            color: gold,
            size: 42,
          ),
        ),
        const SizedBox(height: 15),
        const Center(
          child: Text(
            'FLIXORA',
            style: TextStyle(
              color: gold,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 3,
            ),
          ),
        ),
        const SizedBox(height: 25),
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
        _profileTile(
          Icons.refresh,
          'Refresh Movies',
          loadHome,
        ),
        const SizedBox(height: 25),
        const Text(
          'Flixora — Movies, made simple.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
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
        trailing: const Icon(
          Icons.chevron_right,
          color: Colors.white54,
        ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Tooltip(
              message: _online ? 'Internet connected' : 'No internet connection',
              child: Icon(
                _online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                color: _online ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
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
          IconButton(
            onPressed: loadHome,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: white),
              decoration: InputDecoration(
                hintText: 'Search movies...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(
                  Icons.search,
                  color: gold,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white54,
                        ),
                      ),
                filled: true,
                fillColor: panel,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: !_connectionKnown
          ? const Center(
              child: CircularProgressIndicator(color: gold),
            )
          : (!_online && _allMovies().isEmpty)
              ? const NoInternetScreen()
              : _currentPage(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          FocusScope.of(context).unfocus();
          setState(() {
            _search = '';
            _searchController.clear();
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
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Liked',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
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

class DownloadsScreen extends StatelessWidget {
  final List<DownloadTask> tasks;
  final Future<void> Function(DownloadTask) onDelete;
  final ValueChanged<DownloadTask> onPlay;

  const DownloadsScreen({
    super.key,
    required this.tasks,
    required this.onDelete,
    required this.onPlay,
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      task.status,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: Colors.white12,
                      color: gold,
                    ),
                    if (task.filePath != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        task.filePath!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Play downloaded movie',
                    onPressed: task.status == 'Completed' && task.filePath != null ? () => onPlay(task) : null,
                    icon: const Icon(Icons.play_circle_fill, color: gold),
                  ),
                  IconButton(
                    tooltip: 'Delete download',
                    onPressed: task.status == 'Completed' ? () => onDelete(task) : null,
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
class MovieDetailsScreen extends StatelessWidget {
  final Movie movie;
  final bool isOnline;
  final bool isFavourite;
  final bool isSaved;
  final VoidCallback onFavourite;
  final VoidCallback onSave;
  final VoidCallback onDownload;
  final VoidCallback onWatch;

  const MovieDetailsScreen({
    super.key,
    required this.movie,
    required this.isOnline,
    required this.isFavourite,
    required this.isSaved,
    required this.onFavourite,
    required this.onSave,
    required this.onDownload,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            backgroundColor: bg,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  movie.backdropUrl.isNotEmpty
                      ? FlixoraCachedImage(
                          isOnline: isOnline,
                          imageUrl: movie.backdropUrl,
                          fit: BoxFit.cover,
                        )
                      : Container(color: panel),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, bg],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 115,
                          height: 165,
                          child: movie.posterUrl.isNotEmpty
                              ? FlixoraCachedImage(
                                  isOnline: isOnline,
                                  imageUrl: movie.posterUrl,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: panel,
                                  child: const Icon(
                                    Icons.movie,
                                    color: gold,
                                    size: 40,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 17),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              movie.title,
                              style: const TextStyle(
                                color: white,
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              movie.year,
                              style: const TextStyle(
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: gold,
                                  size: 18,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  movie.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (movie.runtime != null &&
                                movie.runtime! > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${movie.runtime} min',
                                style: const TextStyle(
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (movie.genres.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: movie.genres
                          .map(
                            (genre) => Chip(
                              label: Text(genre),
                              backgroundColor: panel,
                              labelStyle: const TextStyle(
                                color: goldLight,
                                fontSize: 11,
                              ),
                              side: BorderSide.none,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Overview',
                    style: TextStyle(
                      color: white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    movie.overview.isEmpty
                        ? 'No description available.'
                        : movie.overview,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.6,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 25),
                  if (movie.videoUrl.trim().isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: onWatch,
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 27,
                        ),
                        label: const Text(
                          'WATCH NOW',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onFavourite,
                          icon: Icon(
                            isFavourite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: gold,
                          ),
                          label: Text(
                            isFavourite ? 'Liked' : 'Favourite',
                            style: const TextStyle(color: white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onSave,
                          icon: Icon(
                            isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: gold,
                          ),
                          label: Text(
                            isSaved ? 'Saved' : 'Save',
                            style: const TextStyle(color: white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (movie.downloadUrl.trim().isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onDownload,
                        icon: const Icon(
                          Icons.download,
                          color: gold,
                        ),
                        label: const Text(
                          'Download Movie',
                          style: TextStyle(color: white),
                        ),
                      ),
                    ),
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
  final Movie movie;
  final String? localFilePath;

  const MoviePlayerScreen({
    super.key,
    required this.movie,
    this.localFilePath,
  });

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<bool>? _completedSubscription;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isFullscreen = false;
  bool _isDisposed = false;
  bool _initialized = false;
  bool _isOpening = false;

  String? _errorMessage;

  double _speed = 1.0;
  double _volume = 100;

  Timer? _hideTimer;

  Tracks _tracks = Tracks(
    video: [VideoTrack.auto()],
    audio: [AudioTrack.auto()],
    subtitle: [SubtitleTrack.auto()],
  );

  String get _resumeKey {
    final id = widget.movie.tmdbId > 0
        ? widget.movie.tmdbId
        : widget.movie.id;

    return 'flixora_resume_$id';
  }

  bool get _validVideoUrl {
    if (widget.localFilePath != null) return true;
    final uri = Uri.tryParse(widget.movie.videoUrl.trim());

    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();

    _player = Player();
    _videoController = VideoController(_player);

    _attachPlayerListeners();
    _initializePlayer();
  }

  // Listeners are attached once. Retrying playback will not create
  // duplicate stream subscriptions.
  void _attachPlayerListeners() {
    _positionSubscription = _player.stream.position.listen((value) {
      if (!mounted || _isDisposed) return;

      setState(() => _position = value);

      if (_duration.inSeconds > 0) {
        _saveResumePosition(value);
      }
    });

    _durationSubscription = _player.stream.duration.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() => _duration = value);
    });

    _playingSubscription = _player.stream.playing.listen((value) {
      if (!mounted || _isDisposed) return;

      setState(() => _isPlaying = value);

      if (value) {
        _startHideTimer();
      } else {
        _cancelHideTimer();
        setState(() => _showControls = true);
      }
    });

    _bufferingSubscription = _player.stream.buffering.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() => _isBuffering = value);
    });

    _errorSubscription = _player.stream.error.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() => _errorMessage = value);
    });

    _tracksSubscription = _player.stream.tracks.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() => _tracks = value);
    });

    _completedSubscription = _player.stream.completed.listen((completed) {
      if (!completed || !mounted || _isDisposed) return;

      setState(() {
        _isPlaying = false;
        _showControls = true;
      });

      _clearResumePosition();
    });
  }

  Future<void> _initializePlayer() async {
    if (_isOpening || _isDisposed) return;

    if (!_validVideoUrl) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Invalid or unavailable video URL.';
        });
      }
      return;
    }

    _isOpening = true;

    try {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _initialized = false;
        });
      }

      final playbackSource = widget.localFilePath ?? widget.movie.videoUrl.trim();
      if (widget.localFilePath != null && !await File(widget.localFilePath!).exists()) {
        throw Exception('Downloaded file is missing.');
      }
      await _player.open(Media(playbackSource));

      if (!mounted || _isDisposed) return;

      setState(() => _initialized = true);

      await _restoreResumePosition();
      _startHideTimer();
    } catch (e) {
      if (!mounted || _isDisposed) return;

      setState(() {
        _errorMessage =
            'Unable to play this video. Please check the video link and try again.';
      });
    } finally {
      _isOpening = false;
    }
  }

  Future<void> _restoreResumePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSeconds = prefs.getInt(_resumeKey) ?? 0;

      if (savedSeconds <= 5) return;

      final savedPosition = Duration(seconds: savedSeconds);

      if (_duration.inSeconds > 0 &&
          savedPosition >= _duration - const Duration(seconds: 15)) {
        await prefs.remove(_resumeKey);
        return;
      }

      await _player.seek(savedPosition);

      if (mounted && !_isDisposed) {
        setState(() => _position = savedPosition);
      }
    } catch (_) {}
  }

  Future<void> _saveResumePosition(Duration position) async {
    if (_isDisposed || _duration.inSeconds <= 0) return;
    if (position.inSeconds < 5) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_resumeKey, position.inSeconds);
    } catch (_) {}
  }

  Future<void> _clearResumePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_resumeKey);
    } catch (_) {}
  }

  void _startHideTimer() {
    _cancelHideTimer();

    if (!_isPlaying || _isLocked) return;

    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _isDisposed) return;
      setState(() => _showControls = false);
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _toggleControls() {
    if (_isLocked) return;

    setState(() => _showControls = !_showControls);

    if (_showControls) {
      _startHideTimer();
    } else {
      _cancelHideTimer();
    }
  }

  Future<void> _togglePlay() async {
    if (_isDisposed) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }

    _startHideTimer();
  }

  Future<void> _seekBy(int seconds) async {
    if (_duration.inMilliseconds <= 0) return;

    final next = _position + Duration(seconds: seconds);

    final clamped = next < Duration.zero
        ? Duration.zero
        : next > _duration
            ? _duration
            : next;

    await _player.seek(clamped);

    if (mounted && !_isDisposed) {
      setState(() => _position = clamped);
    }

    _startHideTimer();
  }

  Future<void> _seekTo(double value) async {
    final target = Duration(milliseconds: value.round());

    await _player.seek(target);

    if (mounted && !_isDisposed) {
      setState(() => _position = target);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _changeSpeed(double speed) async {
    await _player.setRate(speed);

    if (!mounted || _isDisposed) return;

    setState(() => _speed = speed);
    _startHideTimer();
  }

  Future<void> _changeVolume(double value) async {
    final volume = value.clamp(0.0, 100.0);

    await _player.setVolume(volume);

    if (!mounted || _isDisposed) return;

    setState(() => _volume = volume);
  }

  Future<void> _toggleFullscreen() async {
    if (!mounted) return;

    if (!_isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
    }

    if (!mounted) return;

    setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<void> _selectAudioTrack(AudioTrack track) async {
    await _player.setAudioTrack(track);

    if (mounted) Navigator.pop(context);
    _startHideTimer();
  }

  Future<void> _selectSubtitleTrack(SubtitleTrack track) async {
    await _player.setSubtitleTrack(track);

    if (mounted) Navigator.pop(context);
    _startHideTimer();
  }

  Future<void> _addExternalSubtitle() async {
    final controller = TextEditingController();

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text(
            'External Subtitle',
            style: TextStyle(color: white),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: white),
            decoration: const InputDecoration(
              hintText: 'Enter subtitle URL',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid subtitle URL.'),
          ),
        );
      }
      return;
    }

    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          url,
          title: 'External Subtitle',
          language: 'external',
        ),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('External subtitle added.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load this subtitle.'),
          ),
        );
      }
    }
  }

  void _showAudioTracks() {
    final audioTracks = _tracks.audio;

    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audio Track',
                  style: TextStyle(
                    color: white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                if (audioTracks.isEmpty)
                  const Text(
                    'No audio tracks available.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ...audioTracks.map((track) {
                  return ListTile(
                    leading: const Icon(
                      Icons.audiotrack,
                      color: gold,
                    ),
                    title: Text(
                      track.title ?? track.language ?? 'Audio',
                      style: const TextStyle(color: white),
                    ),
                    onTap: () => _selectAudioTrack(track),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSubtitleTracks() {
    final subtitleTracks = _tracks.subtitle;

    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subtitles',
                  style: TextStyle(
                    color: white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(
                    Icons.subtitles_off,
                    color: gold,
                  ),
                  title: const Text(
                    'Off',
                    style: TextStyle(color: white),
                  ),
                  onTap: () => _selectSubtitleTrack(
                    SubtitleTrack.no(),
                  ),
                ),
                ...subtitleTracks.map((track) {
                  return ListTile(
                    leading: const Icon(
                      Icons.subtitles,
                      color: gold,
                    ),
                    title: Text(
                      track.title ?? track.language ?? 'Subtitle',
                      style: const TextStyle(color: white),
                    ),
                    onTap: () => _selectSubtitleTrack(track),
                  );
                }),
                ListTile(
                  leading: const Icon(Icons.add, color: gold),
                  title: const Text(
                    'Add External Subtitle',
                    style: TextStyle(color: white),
                  ),
                  onTap: _addExternalSubtitle,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettings() {
    _cancelHideTimer();

    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      builder: (context) {
        const speeds = [
          0.25,
          0.5,
          0.75,
          1.0,
          1.25,
          1.5,
          1.75,
          2.0,
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 25),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Playback Settings',
                  style: TextStyle(
                    color: white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Playback Speed',
                  style: TextStyle(
                    color: gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: speeds.map((speed) {
                    final selected = _speed == speed;

                    return ChoiceChip(
                      label: Text('${speed}x'),
                      selected: selected,
                      selectedColor: gold,
                      backgroundColor: bg,
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : white,
                      ),
                      onSelected: (_) async {
                        await _changeSpeed(speed);

                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.audiotrack,
                    color: gold,
                  ),
                  title: const Text(
                    'Audio Track',
                    style: TextStyle(color: white),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showAudioTracks();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.subtitles,
                    color: gold,
                  ),
                  title: const Text(
                    'Subtitles',
                    style: TextStyle(color: white),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSubtitleTracks();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.high_quality,
                    color: gold,
                  ),
                  title: const Text(
                    'Video Quality',
                    style: TextStyle(color: white),
                  ),
                  subtitle: Text(
                    _tracks.video.length > 1
                        ? '${_tracks.video.length} video tracks available'
                        : 'Quality depends on the video source',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(_startHideTimer);
  }

  Widget _centerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => _seekBy(-10),
          iconSize: 38,
          color: white,
          icon: const Icon(Icons.replay_10_rounded),
        ),
        const SizedBox(width: 25),
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(
              color: gold.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: IconButton(
            onPressed: _togglePlay,
            iconSize: 38,
            color: gold,
            icon: Icon(
              _isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
        ),
        const SizedBox(width: 25),
        IconButton(
          onPressed: () => _seekBy(10),
          iconSize: 38,
          color: white,
          icon: const Icon(Icons.forward_10_rounded),
        ),
      ],
    );
  }

  Widget _bottomControls() {
    final max = _duration.inMilliseconds.toDouble();
    final current = _position.inMilliseconds
        .toDouble()
        .clamp(0.0, max > 0 ? max : 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(
                  color: white,
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: Slider(
                  value: current,
                  min: 0,
                  max: max > 0 ? max : 1,
                  activeColor: gold,
                  inactiveColor: Colors.white30,
                  onChanged: max > 0
                      ? (value) {
                          setState(() {
                            _position = Duration(
                              milliseconds: value.round(),
                            );
                          });
                        }
                      : null,
                  onChangeEnd: max > 0 ? _seekTo : null,
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  color: white,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => _changeVolume(_volume - 10),
                icon: const Icon(
                  Icons.volume_down,
                  color: white,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  activeColor: gold,
                  inactiveColor: Colors.white24,
                  onChanged: _changeVolume,
                ),
              ),
              IconButton(
                onPressed: () => _changeVolume(_volume + 10),
                icon: const Icon(
                  Icons.volume_up,
                  color: white,
                ),
              ),
              TextButton(
                onPressed: _showSettings,
                child: Text(
                  '${_speed}x',
                  style: const TextStyle(
                    color: gold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _toggleFullscreen,
                icon: Icon(
                  _isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
              widget.movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          IconButton(
            onPressed: _showSettings,
            icon: const Icon(
              Icons.settings,
              color: white,
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _isLocked = true;
                _showControls = false;
              });
              _cancelHideTimer();
            },
            icon: const Icon(
              Icons.lock_outline,
              color: white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerError() {
    return Center(
      child: Padding(
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
              _errorMessage ?? 'Playback error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: white),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
              ),
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerBody() {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Video(
            controller: _videoController,
            fit: BoxFit.contain,
          ),
        ),
        if (_isBuffering)
          const CircularProgressIndicator(color: gold),
        if (_errorMessage != null)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              child: _playerError(),
            ),
          ),
        if (!_initialized && _errorMessage == null)
          const CircularProgressIndicator(color: gold),
        if (_isLocked)
          Positioned(
            left: 15,
            top: 15,
            child: IconButton(
              onPressed: () {
                setState(() {
                  _isLocked = false;
                  _showControls = true;
                });
                _startHideTimer();
              },
              icon: const Icon(
                Icons.lock,
                color: gold,
                size: 28,
              ),
            ),
          ),
        if (!_isLocked)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                final width = MediaQuery.of(context).size.width;

                if (details.localPosition.dx < width / 2) {
                  _seekBy(-10);
                } else {
                  _seekBy(10);
                }
              },
              onDoubleTap: () {},
              child: const SizedBox.expand(),
            ),
          ),
        if (_showControls && !_isLocked && _errorMessage == null)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black87,
                  ],
                  stops: [0, 0.28, 0.62, 1],
                ),
              ),
              child: Column(
                children: [
                  _topControls(),
                  const Spacer(),
                  _centerControls(),
                  const Spacer(),
                  _bottomControls(),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelHideTimer();

    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    _tracksSubscription?.cancel();
    _completedSubscription?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    unawaited(_player.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: _playerBody(),
      ),
    );
  }
}
