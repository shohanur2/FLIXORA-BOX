import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'video_quality_service.dart';

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

List<String> _tmdbGenreNames(dynamic raw) {
  const names = <int, String>{
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
    80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
    14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
    9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi', 10770: 'TV Movie',
    53: 'Thriller', 10752: 'War', 37: 'Western', 10759: 'Action & Adventure',
    10762: 'Kids', 10763: 'News', 10764: 'Reality', 10765: 'Sci-Fi & Fantasy',
    10766: 'Soap', 10767: 'Talk', 10768: 'War & Politics',
  };
  if (raw is List) {
    return raw.map((item) {
      if (item is Map) return (item['name'] ?? '').toString();
      return names[_toInt(item)] ?? '';
    }).where((name) => name.isNotEmpty).toList();
  }
  return [];
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
  final String mediaType;
  final String originalLanguage;
  final String originCountry;

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
    this.mediaType = 'movie',
    this.originalLanguage = '',
    this.originCountry = '',
  });

  bool get isFlixora => source == 'flixora';

  bool get hasPlayableVideoUrl {
    final uri = Uri.tryParse(videoUrl.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Movie withFallbackMetadata(Movie fallback) => Movie(
        id: id,
        tmdbId: tmdbId > 0 ? tmdbId : fallback.tmdbId,
        sourceId: sourceId,
        source: source,
        title: title.trim().isNotEmpty && title != 'Unknown Movie'
            ? title
            : fallback.title,
        year: year != 'N/A' ? year : fallback.year,
        overview: overview.trim().isNotEmpty &&
                overview != 'No description available.'
            ? overview
            : fallback.overview,
        poster: poster.isNotEmpty ? poster : fallback.poster,
        backdrop: backdrop.isNotEmpty ? backdrop : fallback.backdrop,
        rating: rating > 0 ? rating : fallback.rating,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : fallback.releaseDate,
        genres: genres.isNotEmpty ? genres : fallback.genres,
        runtime: runtime ?? fallback.runtime,
        videoUrl: videoUrl.isNotEmpty ? videoUrl : fallback.videoUrl,
        downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : fallback.downloadUrl,
        mediaType: mediaType,
        originalLanguage: originalLanguage.isNotEmpty ? originalLanguage : fallback.originalLanguage,
        originCountry: originCountry.isNotEmpty ? originCountry : fallback.originCountry,
      );

  factory Movie.fromJson(Map<String, dynamic> json, {String? mediaType}) {
    final date = (json['release_date'] ?? json['first_air_date'] ?? '').toString();
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
      genres: _tmdbGenreNames(json['genre_ids'] ?? json['genres']),
      mediaType: mediaType ?? (json['media_type'] ?? 'movie').toString(),
      originalLanguage: (json['original_language'] ?? '').toString(),
      originCountry: ((json['origin_country'] is List && (json['origin_country'] as List).isNotEmpty)
              ? (json['origin_country'] as List).first
              : '').toString(),
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
      mediaType: 'movie',
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
      mediaType: (json['mediaType'] ?? 'movie').toString(),
      originalLanguage: (json['originalLanguage'] ?? '').toString(),
      originCountry: (json['originCountry'] ?? '').toString(),
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
        'mediaType': mediaType,
        'originalLanguage': originalLanguage,
        'originCountry': originCountry,
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
  static const String historyKey = 'flixora_watch_history';
  static const String downloadsKey = 'flixora_downloads';
  static const String trendingTvKey = 'flixora_trending_tv';
  static const String popularTvKey = 'flixora_popular_tv';
  static const String topRatedTvKey = 'flixora_top_rated_tv';
  static const String animeKey = 'flixora_anime';
  static const String koreanKey = 'flixora_korean_drama';
  static const String bengaliMoviesKey = 'flixora_bengali_movies';
  static const String bengaliTvKey = 'flixora_bengali_tv';

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

  static Future<List<Movie>> getMovies(
    String endpoint, {
    Map<String, String> extraParams = const {},
  }) async {
    if (apiKey.isEmpty) throw Exception('Movie service is not configured.');
    final isTv = endpoint.startsWith('tv/') || endpoint.startsWith('discover/tv');
    final uri = Uri.parse('$base/$endpoint').replace(queryParameters: {
      'api_key': apiKey, 'language': 'en-US', 'page': '1', ...extraParams,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Could not load catalogue.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['results'] as List? ?? [];
    return results.whereType<Map>().map((item) => Movie.fromJson(
      Map<String, dynamic>.from(item), mediaType: isTv ? 'tv' : 'movie',
    )).toList();
  }

  static Future<List<Movie>> search(String query) async {
    if (apiKey.isEmpty) throw Exception('Movie service is not configured.');
    Future<List<Movie>> searchType(String type) async {
      final uri = Uri.parse('$base/search/$type').replace(queryParameters: {
        'api_key': apiKey, 'query': query, 'language': 'en-US',
        'page': '1', 'include_adult': 'false',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      return results.whereType<Map>().map((item) => Movie.fromJson(
        Map<String, dynamic>.from(item), mediaType: type,
      )).toList();
    }
    final results = await Future.wait([searchType('movie'), searchType('tv')]);
    return [...results[0], ...results[1]];
  }

  static Future<Map<String, dynamic>> details(
    int id, {String mediaType = 'movie'}
  ) async {
    if (apiKey.isEmpty) throw Exception('Movie service is not configured.');
    final uri = Uri.parse('$base/$mediaType/$id').replace(queryParameters: {
      'api_key': apiKey, 'language': 'en-US',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Could not load title details.');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class FlixoraMovieService {
  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Resolve Admin records to a real video URL before showing them as playable.
  /// Quality rows are keyed by the Supabase movies.id, not the TMDB ID.
  static Future<List<Movie>> mapPlayableRows(
    SupabaseClient client,
    List<dynamic> rawRows,
  ) async {
    final rows = rawRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final movieIds = rows
        .map((row) => _toInt(row['id']))
        .where((id) => id > 0)
        .toList();
    final qualityFallbacks = <int, Map<String, String>>{};

    if (movieIds.isNotEmpty) {
      try {
        final qualityRows = await client
            .from('movie_video_qualities')
            .select('movie_id, quality, video_url')
            .inFilter('movie_id', movieIds);

        for (final item in (qualityRows as List).whereType<Map>()) {
          final row = Map<String, dynamic>.from(item);
          final movieId = _toInt(row['movie_id']);
          final quality = (row['quality'] ?? '').toString().trim();
          final url = (row['video_url'] ?? '').toString().trim();
          if (movieId <= 0 || quality.isEmpty || !_isHttpUrl(url)) continue;

          final current = qualityFallbacks[movieId];
          final currentQuality = current?['quality'] ?? '';
          final is720p = quality.toLowerCase() == '720p';
          final currentIs720p = currentQuality.toLowerCase() == '720p';
          final shouldReplace = current == null ||
              (is720p && !currentIs720p) ||
              (!currentIs720p &&
                  !is720p &&
                  VideoQualityService.rank(quality) >
                      VideoQualityService.rank(currentQuality));

          if (shouldReplace) {
            qualityFallbacks[movieId] = {
              'quality': quality,
              'video_url': url,
            };
          }
        }
      } catch (e) {
        debugPrint('Could not resolve Admin video qualities: $e');
      }
    }

    return rows.map((row) {
      final movieId = _toInt(row['id']);
      final legacyUrl = (row['video_url'] ?? '').toString();
      if (!_isHttpUrl(legacyUrl)) {
        final fallbackUrl = qualityFallbacks[movieId]?['video_url'] ?? '';
        if (_isHttpUrl(fallbackUrl)) row['video_url'] = fallbackUrl;
      }
      return Movie.fromSupabase(row);
    }).where((movie) => movie.sourceId > 0 && movie.hasPlayableVideoUrl).toList();
  }

  static Future<List<Movie>> getPublishedMovies() async {
    final client = supabaseClient;
    if (client == null) return [];

    try {
      final response = await client
          .from('movies')
          .select()
          .eq('is_published', true)
          .order('created_at', ascending: false);

      return mapPlayableRows(client, response as List);
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

      return mapPlayableRows(client, response as List);
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
        fontFamily: 'sans-serif-condensed',
        textTheme: const TextTheme(bodyMedium: TextStyle(fontStyle: FontStyle.italic), bodyLarge: TextStyle(fontStyle: FontStyle.italic), titleMedium: TextStyle(fontStyle: FontStyle.italic), titleLarge: TextStyle(fontStyle: FontStyle.italic)),
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
  List<Movie> trendingTv = [];
  List<Movie> popularTv = [];
  List<Movie> topRatedTv = [];
  List<Movie> anime = [];
  List<Movie> koreanDrama = [];
  List<Movie> bengaliMovies = [];
  List<Movie> bengaliTv = [];
  List<Movie> flixoraMovies = [];
  List<Movie> searchResults = [];

  final Set<int> _favourites = {};
  final Set<int> _saved = {};
  final List<Movie> _watchHistory = [];
  final List<DownloadTask> _downloads = [];
  String? _profileSection;
  bool _studyMode = false;
  bool _notificationsEnabled = true;
  bool _familyMode = false;
  bool _downloadInBackground = false;
  bool _autoMiniPlayer = true;
  String _appLanguage = 'English';
  String _preferredQuality = 'Auto';

  Set<int> get _flixoraTmdbIds {
    return flixoraMovies
        .map((movie) => movie.tmdbId)
        .where((id) => id > 0)
        .toSet();
  }

  List<Movie> _withoutFlixoraDuplicates(List<Movie> movies) {
    final adminIds = _flixoraTmdbIds;

    return movies.where((movie) {
      if (movie.mediaType != 'movie' || movie.tmdbId <= 0) return true;
      return !adminIds.contains(movie.tmdbId);
    }).toList();
  }

  List<Movie> _deduplicateMovies(List<Movie> movies) {
    final seenTmdbIds = <String>{};
    final seenFallbackIds = <String>{};

    return movies.where((movie) {
      if (movie.tmdbId > 0) {
        return seenTmdbIds.add('${movie.mediaType}:${movie.tmdbId}');
      }

      final fallbackKey = '${movie.mediaType}:${movie.source}:${movie.id}';
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
    await _loadAppSettings();
    final savedHistory = await MovieCache.getList(MovieCache.historyKey);
    final prefs = await SharedPreferences.getInstance();
    final savedStudyMode = prefs.getBool('flixora_study_mode') ?? false;
    final savedDownloads = await MovieCache.getDownloads();
    if (mounted) {
      setState(() {
        _watchHistory
          ..clear()
          ..addAll(savedHistory);
        _studyMode = savedStudyMode;
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

  Future<void> _loadAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = prefs.getBool('flixora_notifications') ?? true;
        _familyMode = prefs.getBool('flixora_family_mode') ?? false;
        _downloadInBackground = prefs.getBool('flixora_download_background') ?? false;
        _autoMiniPlayer = prefs.getBool('flixora_auto_miniplayer') ?? true;
        _appLanguage = prefs.getString('flixora_language') ?? 'English';
        _preferredQuality = prefs.getString('flixora_preferred_quality') ?? 'Auto';
      });
    } catch (_) {}
  }

  Future<void> _saveBoolSetting(String key, bool value, void Function(bool) update) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (mounted) setState(() => update(value));
  }

  Future<void> _showLanguagePicker() async {
    const languages = ['English', 'বাংলা', 'हिन्दी'];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: panel,
        title: const Text('Select language', style: TextStyle(color: white)),
        children: languages.map((language) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, language),
          child: Row(children: [
            Expanded(child: Text(language, style: const TextStyle(color: white))),
            if (_appLanguage == language) const Icon(Icons.check, color: gold),
          ]),
        )).toList(),
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flixora_language', selected);
    if (mounted) setState(() => _appLanguage = selected);
    _showMessage('Language preference saved. Full app translation will be added separately.');
  }

  Future<void> _showWatchOptions() async {
    const qualities = ['Auto', '360p', '480p', '720p', '1080p'];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: panel,
        title: const Text('Watch Options', style: TextStyle(color: white)),
        children: [
          RadioGroup<String>(
            groupValue: _preferredQuality,
            onChanged: (value) {
              if (value != null) Navigator.pop(dialogContext, value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: qualities.map((quality) => RadioListTile<String>(
                value: quality,
                activeColor: gold,
                title: Text(quality, style: const TextStyle(color: white)),
              )).toList(),
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flixora_preferred_quality', selected);
    if (mounted) setState(() => _preferredQuality = selected);
  }

  void _showSettingsInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: Text(title, style: const TextStyle(color: white)),
        content: Text(message, style: const TextStyle(color: Colors.white70, height: 1.45)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
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
      MovieCache.getList(MovieCache.trendingTvKey),
      MovieCache.getList(MovieCache.popularTvKey),
      MovieCache.getList(MovieCache.topRatedTvKey),
      MovieCache.getList(MovieCache.animeKey),
      MovieCache.getList(MovieCache.koreanKey),
      MovieCache.getList(MovieCache.bengaliMoviesKey),
      MovieCache.getList(MovieCache.bengaliTvKey),
      MovieCache.getList(MovieCache.flixoraKey),
    ]);

    if (!mounted) return;

    setState(() {
      trending = results[0];
      popular = results[1];
      latest = results[2];
      topRated = results[3];
      trendingTv = results[4];
      popularTv = results[5];
      topRatedTv = results[6];
      anime = results[7];
      koreanDrama = results[8];
      bengaliMovies = results[9];
      bengaliTv = results[10];
      flixoraMovies = results[11];
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
        TmdbService.getMovies('trending/movie/week').catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/popular').catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/now_playing').catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/top_rated').catchError((_) => <Movie>[]),
        TmdbService.getMovies('trending/tv/week').catchError((_) => <Movie>[]),
        TmdbService.getMovies('tv/popular').catchError((_) => <Movie>[]),
        TmdbService.getMovies('tv/top_rated').catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_genres': '16', 'with_origin_country': 'JP',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_origin_country': 'KR|JP|CN|TH|TW',
          'with_original_language': 'ko|ja|zh|th',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'bn', 'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'bn', 'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        FlixoraMovieService.getPublishedMovies().catchError((_) => <Movie>[]),
      ]);

      if (!mounted) return;

      setState(() {
        trending = results[0];
        popular = results[1];
        latest = results[2];
        topRated = results[3];
        trendingTv = results[4];
        popularTv = results[5];
        topRatedTv = results[6];
        anime = results[7];
        koreanDrama = results[8];
        bengaliMovies = results[9];
        bengaliTv = results[10];
        flixoraMovies = results[11];
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
        MovieCache.saveList(MovieCache.trendingTvKey, trendingTv),
        MovieCache.saveList(MovieCache.popularTvKey, popularTv),
        MovieCache.saveList(MovieCache.topRatedTvKey, topRatedTv),
        MovieCache.saveList(MovieCache.animeKey, anime),
        MovieCache.saveList(MovieCache.koreanKey, koreanDrama),
        MovieCache.saveList(MovieCache.bengaliMoviesKey, bengaliMovies),
        MovieCache.saveList(MovieCache.bengaliTvKey, bengaliTv),
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
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...anime,
      ...koreanDrama,
      ...bengaliMovies,
      ...bengaliTv,
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

  void _recordWatch(Movie movie) {
    _watchHistory.removeWhere((item) =>
        item.id == movie.id ||
        (movie.tmdbId > 0 && item.tmdbId == movie.tmdbId));
    _watchHistory.insert(0, movie);
    if (_watchHistory.length > 30) {
      _watchHistory.removeRange(30, _watchHistory.length);
    }
    unawaited(MovieCache.saveList(MovieCache.historyKey, _watchHistory));
    if (mounted) setState(() {});
  }

  void _openDownloadsTab() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;
    setState(() {
      _tab = 1;
      _profileSection = null;
      _search = '';
      _searchController.clear();
      _searchLoading = false;
    });
  }

  void _openProfileSection(String section) {
    setState(() => _profileSection = section);
  }

  Movie? _cachedFlixoraMatch(Movie movie) {
    if (movie.tmdbId <= 0) return null;
    for (final candidate in [...flixoraMovies, ...searchResults]) {
      if (candidate.isFlixora && candidate.tmdbId == movie.tmdbId) {
        return candidate;
      }
    }
    return null;
  }

  /// Resolve every entry point to the same Admin-managed movie record.
  /// TMDB IDs are external IDs; video qualities are keyed by movies.id.
  Future<Movie?> _resolveMovieForOpening(Movie requested) async {
    final client = supabaseClient;

    if (!_online || client == null) {
      return requested.isFlixora || requested.mediaType == 'tv'
          ? requested
          : (_cachedFlixoraMatch(requested) ?? requested);
    }

    try {
      dynamic response;
      if (requested.isFlixora && requested.sourceId > 0) {
        response = await client
            .from('movies')
            .select()
            .eq('id', requested.sourceId)
            .limit(1);
      } else if (requested.tmdbId > 0 && requested.mediaType == 'movie') {
        response = await client
            .from('movies')
            .select()
            .eq('tmdb_id', requested.tmdbId)
            .order('created_at', ascending: false)
            .limit(1);
      }

      if (response is List && response.isNotEmpty) {
        final row = Map<String, dynamic>.from(response.first as Map);
        // An Admin record takes priority even when it is unpublished.
        if (row['is_published'] != true) return null;

        final playable = await FlixoraMovieService.mapPlayableRows(
          client,
          [row],
        );
        if (playable.isEmpty) return null;

        // Keep the Admin source/status, but fill missing catalogue metadata
        // from TMDB so incomplete Admin fields do not blank the details page.
        return playable.first.withFallbackMetadata(requested);
      }

      if (requested.isFlixora) return null;
      if (requested.mediaType == 'tv') return requested;
      return _cachedFlixoraMatch(requested) ?? requested;
    } catch (e) {
      debugPrint('Could not resolve Admin movie record: $e');
      // Keep the already-loaded published Admin entry usable if the network
      // lookup fails; otherwise fall back to the requested TMDB catalogue item.
      return requested.isFlixora || requested.mediaType == 'tv'
          ? requested
          : (_cachedFlixoraMatch(requested) ?? requested);
    }
  }

  Future<void> _openMovie(Movie movie) async {
    final resolvedMovie = await _resolveMovieForOpening(movie);
    if (!mounted) return;

    if (resolvedMovie == null) {
      _showMessage('This movie is currently unavailable.');
      return;
    }

    final selectedMovie = resolvedMovie;
    final isFavourite = _favourites.contains(selectedMovie.id) ||
        _favourites.contains(movie.id);
    final isSaved = _saved.contains(selectedMovie.id) ||
        _saved.contains(movie.id);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailsScreen(
          movie: selectedMovie,
          isOnline: _online,
          isFavourite: isFavourite,
          isSaved: isSaved,
          onShare: () => Share.share(
            '${selectedMovie.title} (${selectedMovie.year}) on FLIXORA',
          ),
          onFavourite: () => _toggleFavourite(selectedMovie),
          onSave: () => _toggleSaved(selectedMovie),
          onDownload: () => addDownload(selectedMovie),
          onWatch: () async {
            _recordWatch(selectedMovie);
            DownloadTask? downloaded;
            for (final task in _downloads) {
              final matchesMovie = task.movieId == selectedMovie.id ||
                  task.movieId == movie.id ||
                  (selectedMovie.tmdbId > 0 &&
                      task.movieId == selectedMovie.tmdbId);
              if (matchesMovie &&
                  task.status == 'Completed' &&
                  task.filePath != null &&
                  File(task.filePath!).existsSync()) {
                downloaded = task;
                break;
              }
            }
            if (downloaded != null) {
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => MoviePlayerScreen(
                  movie: selectedMovie,
                  localFilePath: downloaded!.filePath,
                  recommendedMovies: _allMovies(),
                  onMovieSelected: _openMovie,
                  onSave: () => _toggleSaved(selectedMovie),
                  onDownload: () => addDownload(selectedMovie),
                  onViewDownloads: () {
                    if (!mounted) return;
                    _openDownloadsTab();
                  },
                  isOnline: _online,
                ),
              ));
              return;
            }
            if (!_online || !await InternetService.isOnline()) {
              if (mounted) {
                setState(() {
                  _online = false;
                  _connectionKnown = true;
                });
                _showMessage('Check your internet connection');
              }
              return;
            }
            if (!mounted) return;
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => MoviePlayerScreen(
                movie: selectedMovie,
                recommendedMovies: _allMovies(),
                onMovieSelected: _openMovie,
                onSave: () => _toggleSaved(selectedMovie),
                onDownload: () => addDownload(selectedMovie),
                onViewDownloads: () {
                  if (!mounted) return;
                  _openDownloadsTab();
                },
                isOnline: _online,
              ),
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
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _sliderController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _slide = index);
            },
            itemBuilder: (context, index) {
              final movie = slides[index];

              return GestureDetector(
                onTap: () => _openMovie(movie),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    movie.backdropUrl.isEmpty
                        ? Container(color: panel)
                        : CachedNetworkImage(
                            imageUrl: movie.backdropUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: panel),
                            errorWidget: (_, __, ___) => Container(color: panel),
                          ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x55000000), Color(0x08000000), Colors.transparent, Color(0xFF080808)],
                          stops: [0, 0.28, 0.58, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            top: 72,
            left: 0,
            right: 0,
            child: _homeCategoryStrip(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: _featuredQuickCards([
              ..._withoutFlixoraDuplicates(trending).take(5).toList().skip(_slide),
              ..._withoutFlixoraDuplicates(trending).take(5).toList().take(_slide),
            ]),
          ),
          Positioned(
            bottom: 8,
            right: 18,
            child: Row(
              children: List.generate(
                slides.length,
                (index) => Container(
                  margin: const EdgeInsets.only(left: 5),
                  width: _slide == index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _slide == index ? Colors.white : Colors.white54,
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

  Widget _featuredQuickCards(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 86,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          final typeLabel = movie.mediaType == 'tv' ? 'TV Series' : 'Movie';

          return GestureDetector(
            onTap: () => _openMovie(movie),
            child: Container(
              width: 265,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: movie.posterUrl.isEmpty
                        ? Container(
                            width: 48,
                            height: 70,
                            color: const Color(0xFF292929),
                            child: const Icon(Icons.movie, color: gold),
                          )
                        : CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            width: 48,
                            height: 70,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 48,
                              height: 70,
                              color: const Color(0xFF292929),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 48,
                              height: 70,
                              color: const Color(0xFF292929),
                              child: const Icon(Icons.movie, color: gold),
                            ),
                          ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$typeLabel  •  ${movie.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  const CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.greenAccent,
                    child: Icon(Icons.play_arrow, color: Colors.black, size: 21),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _homeCategory = 'Trending';

  List<Movie> _moviesForHomeCategory(String category) {
    switch (category) {
      case 'Trending':
        return _deduplicateMovies([
          ...flixoraMovies, ...trending, ...trendingTv,
        ]);
      case 'Movies':
        return _deduplicateMovies([
          ...flixoraMovies, ...trending, ...popular, ...latest, ...topRated,
        ].where((movie) => movie.mediaType == 'movie').toList());
      case 'TV Series':
        return _deduplicateMovies([
          ...trendingTv, ...popularTv, ...topRatedTv, ...koreanDrama, ...bengaliTv,
        ]);
      case 'Anime':
        return anime;
      case 'Korean Drama':
        return koreanDrama;
      case 'Bengali':
        return [...bengaliMovies, ...bengaliTv];
      case 'Flixora Originals':
        return flixoraMovies;
      default:
        return [];
    }
  }

  Widget _homeCategoryStrip() {
    const categories = [
      'Trending', 'Anime', 'Movies', 'TV Series',
      'Korean Drama', 'Bengali', 'Flixora Originals',
    ];

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = _homeCategory == category;

          return GestureDetector(
            onTap: () => setState(() => _homeCategory = category),
            child: Center(
              child: Text(
                category,
                style: TextStyle(
                  color: selected ? white : Colors.white60,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  fontFamily: 'sans-serif-condensed',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _homeContent() {
    if (_homeCategory != 'Trending') {
      final movies = _moviesForHomeCategory(_homeCategory);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(child: Text(
                  _homeCategory,
                  style: const TextStyle(
                    color: white, fontSize: 20, fontWeight: FontWeight.bold,
                  ),
                )),
                TextButton(
                  onPressed: () => setState(() => _homeCategory = 'Trending'),
                  child: const Text('Show all'),
                ),
              ],
            ),
          ),
          Expanded(child: _collectionContent(_homeCategory, movies)),
        ],
      );
    }

    return RefreshIndicator(
      color: gold,
      backgroundColor: panel,
      onRefresh: loadHome,
      child: ListView(
        children: [
          _featuredSlider(),
          if (flixoraMovies.isNotEmpty) ...[
            _sectionTitle('Flixora Originals'),
            _movieRow(flixoraMovies),
          ],
          _sectionTitle('Trending Movies'),
          _movieRow(_withoutFlixoraDuplicates(trending)),
          _sectionTitle('Trending TV Series'),
          _movieRow(trendingTv),
          _sectionTitle('Anime'),
          _movieRow(anime),
          _sectionTitle('Korean & Asian Drama'),
          _movieRow(koreanDrama),
          _sectionTitle('Bengali Movies'),
          _movieRow(bengaliMovies),
          _sectionTitle('Bengali TV Series'),
          _movieRow(bengaliTv),
          _sectionTitle('Popular Movies'),
          _movieRow(_withoutFlixoraDuplicates(popular)),
          _sectionTitle('Popular TV Series'),
          _movieRow(popularTv),
          _sectionTitle('Now Playing'),
          _movieRow(_withoutFlixoraDuplicates(latest)),
          _sectionTitle('Top Rated Movies'),
          _movieRow(_withoutFlixoraDuplicates(topRated)),
          _sectionTitle('Top Rated TV Series'),
          _movieRow(topRatedTv),
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
        Navigator.push(context, MaterialPageRoute(builder: (_) => MoviePlayerScreen(
            movie: movie,
            localFilePath: task.filePath,
            recommendedMovies: _allMovies(),
            onMovieSelected: _openMovie,
            isOnline: _online,
          )));
      },
    );
  }

  Widget _profileContent() {
    final user = supabaseClient?.auth.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 29,
              backgroundColor: panel,
              child: Icon(Icons.person, color: gold, size: 32),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.email ?? 'FLIXORA Visitor',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white, fontSize: 17, fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user == null ? 'Sign in to sync your account' : 'Visitor account',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: user == null ? _showVisitorLogin : _signOutVisitor,
              child: Text(user == null ? 'Login' : 'Logout'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _profileGroup([
          _profileTile(Icons.card_giftcard, 'Rewards Center',
              () => _openProfileSection('Rewards Center')),
        ]),
        const SizedBox(height: 12),
        _watchHistoryPreview(),
        const SizedBox(height: 12),
        _profileGroup([
          _profileTile(Icons.bookmark_outline, 'My List',
              () => _openProfileSection('My List'),
              trailingText: '${_saved.length}'),
          _profileTile(Icons.favorite_outline, 'My Favourites',
              () => _openProfileSection('My Favourites'),
              trailingText: '${_favourites.length}'),
          _profileTile(Icons.notifications_none, 'Messages',
              () => _openProfileSection('Messages'),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54)),
          _profileTile(Icons.live_tv_outlined, 'TV Download & Web Link',
              () => _openProfileSection('TV Download & Web Link'),
              trailing: const Text('NEW', style: TextStyle(
                color: white, backgroundColor: Colors.red, fontSize: 10,
              ))),
        ]),
        const SizedBox(height: 14),
        _profileGroup([
          _profileTile(Icons.groups_outlined, 'Community',
              () => _openProfileSection('Community')),
          _profileTile(Icons.chat_bubble_outline, 'My Activity',
              () => _openProfileSection('My Activity')),
        ]),
        const SizedBox(height: 14),
        _profileGroup([
          _profileTile(Icons.settings_outlined, 'Settings',
              () => _openProfileSection('Settings')),
          _profileTile(Icons.lock_outline, 'Parental PIN',
              _showParentalPinDialog, trailingText: 'Set up'),
          _profileTile(Icons.school_outlined, 'Study Mode',
              _toggleStudyMode, trailingText: _studyMode ? 'On' : 'Off'),
          _profileTile(Icons.feedback_outlined, 'Feedback', () {
            Share.share('I would like to share feedback about FLIXORA.');
          }),
        ]),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'FLIXORA  •  Movies, made simple.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _watchHistoryPreview() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 2, 10),
        child: Row(children: [
          const Icon(Icons.history, color: Colors.white70, size: 20),
          const SizedBox(width: 9),
          const Expanded(child: Text('Watch History', style: TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))),
          Text('${_watchHistory.length}', style: const TextStyle(color: Colors.white54)),
          IconButton(tooltip: 'View all watch history', onPressed: () => _openProfileSection('Watch History'), icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 25)),
        ]),
      ),
      if (_watchHistory.isEmpty)
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text('Movies you play will appear here.', style: TextStyle(color: Colors.white54)))
      else
        SizedBox(height: 112, child: ListView.separated(
          scrollDirection: Axis.horizontal, itemCount: _watchHistory.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final movie = _watchHistory[index];
            final image = movie.backdropUrl.isNotEmpty ? movie.backdropUrl : movie.posterUrl;
            return GestureDetector(onTap: () => _openMovie(movie), child: SizedBox(width: 148, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 148, height: 78, child: FlixoraCachedImage(imageUrl: image, isOnline: _online))),
              const SizedBox(height: 5),
              Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontSize: 12, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
            ])));
          },
        )),
    ]);
  }

  Widget _watchHistoryPage() {
    if (_watchHistory.isEmpty) return _profileMessagePage(Icons.history, 'No watch history yet', 'Movies you start watching will appear here.');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), itemCount: _watchHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final movie = _watchHistory[index];
        final image = movie.backdropUrl.isNotEmpty ? movie.backdropUrl : movie.posterUrl;
        return Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 116, height: 78, child: Stack(fit: StackFit.expand, children: [
            FlixoraCachedImage(imageUrl: image, isOnline: _online),
            Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), color: Colors.black54, child: Text(movie.year, style: const TextStyle(color: white, fontSize: 10, fontWeight: FontWeight.bold)))),
          ]))),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontSize: 15, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
            const SizedBox(height: 7),
            const Text('Recently watched', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
          ])),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white60), color: panel,
            onSelected: (value) async {
              if (value == 'remove') {
                setState(() => _watchHistory.removeWhere((item) => item.id == movie.id));
                await MovieCache.saveList(MovieCache.historyKey, _watchHistory);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove from history'))],
          ),
          IconButton(tooltip: 'Play', onPressed: () => _openMovie(movie), icon: const CircleAvatar(radius: 17, backgroundColor: Colors.white70, child: Icon(Icons.play_arrow, color: Colors.black, size: 21))),
        ]);
      },
    );
  }

  Widget _profileGroup(List<Widget> children) {
    return Card(
      color: panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      child: Column(children: children),
    );
  }

  Widget _profileTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    String? trailingText,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(
        color: white, fontWeight: FontWeight.w600,
      )),
      trailing: trailing ?? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(trailingText,
                  style: const TextStyle(color: Colors.white54)),
            ),
          const Icon(Icons.chevron_right, color: Colors.white54),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _profileSectionContent() {
    switch (_profileSection) {
      case 'Watch History':
        return _watchHistoryPage();
      case 'My List':
        return _collectionContent('My List', _moviesForIds(_saved));
      case 'My Favourites':
        return _collectionContent('My Favourites', _moviesForIds(_favourites));
      case 'My Activity':
        return _collectionContent('My Activity', _watchHistory);
      case 'Settings':
        return _settingsContent();
      case 'Rewards Center':
        return _profileMessagePage(
          Icons.card_giftcard, 'Rewards are coming soon',
          'FLIXORA rewards are not enabled yet.',
        );
      case 'Messages':
        return _profileMessagePage(
          Icons.notifications_none, 'No new messages',
          'You are all caught up. FLIXORA messages will appear here.',
        );
      case 'TV Download & Web Link':
        return _profileMessagePage(
          Icons.live_tv_outlined, 'TV links are not connected yet',
          'This section is reserved for verified TV download and web links.',
        );
      case 'Community':
        return _profileMessagePage(
          Icons.groups_outlined, 'Community is coming soon',
          'Community features are not connected in this version.',
        );
      default:
        return _profileContent();
    }
  }

  Widget _settingSwitch({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return SwitchListTile(
      value: value, onChanged: onChanged, activeThumbColor: Colors.white,
      activeTrackColor: const Color(0xFF22DCA0), inactiveThumbColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      title: Text(title, style: const TextStyle(color: white, fontSize: 15, fontStyle: FontStyle.italic)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 7), child: Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  Widget _settingsContent() {
    final user = supabaseClient?.auth.currentUser;
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 16), children: [
        const Padding(padding: EdgeInsets.fromLTRB(4, 2, 4, 9), child: Text('Your app and preferences', style: TextStyle(color: Colors.white70, fontSize: 13))),
        _profileGroup([
          _profileTile(Icons.notifications_none, 'Notifications', () => _saveBoolSetting('flixora_notifications', !_notificationsEnabled, (x) => _notificationsEnabled = x),
            trailing: Switch(value: _notificationsEnabled, onChanged: (v) => _saveBoolSetting('flixora_notifications', v, (x) => _notificationsEnabled = x), activeThumbColor: Colors.white, activeTrackColor: const Color(0xFF22DCA0))),
          _profileTile(Icons.language, 'Language', _showLanguagePicker, trailingText: _appLanguage),
          _profileTile(Icons.tune, 'Watch Options', _showWatchOptions, trailingText: _preferredQuality),
          _settingSwitch(title: 'Family Mode', subtitle: 'Helps keep the catalogue suitable for family viewing.', value: _familyMode, onChanged: (v) => _saveBoolSetting('flixora_family_mode', v, (x) => _familyMode = x)),
          _settingSwitch(title: 'Download in background', subtitle: 'Keep download tasks active while you use other screens.', value: _downloadInBackground, onChanged: (v) => _saveBoolSetting('flixora_download_background', v, (x) => _downloadInBackground = x)),
          _settingSwitch(title: 'Auto activate Miniplayer', subtitle: 'Miniplayer behavior will be connected when the player feature is extended.', value: _autoMiniPlayer, onChanged: (v) => _saveBoolSetting('flixora_auto_miniplayer', v, (x) => _autoMiniPlayer = x)),
          _profileTile(Icons.privacy_tip_outlined, 'Privacy Settings', () => _showSettingsInfo('Privacy Settings', 'Your watch history, saved list and app preferences are currently stored on this device. Account sync and privacy controls will be expanded with the visitor account backend.')),
        ]),
        const SizedBox(height: 20),
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 9), child: Text('More info and support', style: TextStyle(color: Colors.white70, fontSize: 13))),
        _profileGroup([
          _profileTile(Icons.system_update, 'Check update', () => _showSettingsInfo('Check update', 'Automatic update checking is not connected to a release service yet. Install new FLIXORA versions from the official release when available.')),
          _profileTile(Icons.info_outline, 'About us', () => _showSettingsInfo('About FLIXORA', 'FLIXORA is a free movie and series discovery and streaming app.')),
          _profileTile(Icons.policy_outlined, 'Privacy Policy', () => _showSettingsInfo('Privacy Policy', 'The public privacy policy page will be added before release.')),
          _profileTile(Icons.description_outlined, 'User Agreement', () => _showSettingsInfo('User Agreement', 'The user agreement page will be added before release.')),
        ]),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 10), child: SizedBox(width: double.infinity, height: 54, child: DecoratedBox(
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF20B9F2), Color(0xFF21E99A)]), borderRadius: BorderRadius.circular(9)),
        child: TextButton(onPressed: user == null ? _showVisitorLogin : _signOutVisitor,
          child: Text(user == null ? 'Log in/Sign up' : 'Log out', style: const TextStyle(color: Color(0xFF06110E), fontSize: 17, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic))),
      ))),
    ]);
  }

  Widget _profileMessagePage(IconData icon, String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: gold, size: 54),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(color: white, fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _showVisitorLogin() async {
    final client = supabaseClient;
    if (client == null) {
      _showMessage('Visitor login is unavailable until the account service is configured.');
      return;
    }
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    var isSignUp = false;
    var busy = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: panel,
          title: Text(isSignUp ? 'Create visitor account' : 'Visitor Login',
              style: const TextStyle(color: white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: white),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: white),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => setDialogState(() {
                isSignUp = !isSignUp;
                errorText = null;
              }),
              child: Text(isSignUp ? 'I have an account' : 'Create account'),
            ),
            FilledButton(
              onPressed: busy ? null : () async {
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (!email.contains('@') || password.length < 6) {
                  setDialogState(() => errorText =
                      'Enter a valid email and a password of at least 6 characters.');
                  return;
                }
                setDialogState(() { busy = true; errorText = null; });
                try {
                  if (isSignUp) {
                    final response = await client.auth.signUp(
                      email: email, password: password,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) {
                      setState(() {});
                      _showMessage(response.session == null
                          ? 'Account created. Check your email if verification is required.'
                          : 'Visitor account created and signed in.');
                    }
                  } else {
                    await client.auth.signInWithPassword(
                      email: email, password: password,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) {
                      setState(() {});
                      _showMessage('Visitor login successful.');
                    }
                  }
                } catch (error) {
                  setDialogState(() {
                    busy = false;
                    errorText = error.toString().replaceFirst('Exception: ', '');
                  });
                }
              },
              child: busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isSignUp ? 'Create account' : 'Login'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> _signOutVisitor() async {
    try {
      await supabaseClient?.auth.signOut();
      if (mounted) {
        setState(() {});
        _showMessage('Logged out.');
      }
    } catch (error) {
      _showMessage('Could not log out: $error');
    }
  }

  Future<void> _showParentalPinDialog() async {
    final controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    final existingPin = prefs.getString('flixora_parental_pin');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: Text(existingPin == null ? 'Set Parental PIN' : 'Change Parental PIN',
            style: const TextStyle(color: white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          style: const TextStyle(color: white),
          decoration: const InputDecoration(
            labelText: '4–6 digit PIN',
            counterStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final pin = controller.text.trim();
              if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                _showMessage('PIN must contain 4 to 6 digits.');
                return;
              }
              await prefs.setString('flixora_parental_pin', pin);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) _showMessage('Parental PIN saved on this device.');
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _toggleStudyMode() async {
    final nextValue = !_studyMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flixora_study_mode', nextValue);
    if (!mounted) return;
    setState(() => _studyMode = nextValue);
    _showMessage(nextValue
        ? 'Study Mode enabled.'
        : 'Study Mode disabled.');
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
        return _downloadsContent();
      case 2:
        return _profileSection == null
            ? _profileContent()
            : _profileSectionContent();
      default:
        return _homeContent();
    }
  }

  String _pageTitle() {
    if (_search.isNotEmpty) return 'Search Results';

    if (_tab == 1) return 'Downloads';
    if (_tab == 2) return _profileSection ?? 'Me';
    return 'FLIXORA';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: _tab == 0 && _search.isEmpty,
      appBar: AppBar(
        backgroundColor: _tab == 0 && _search.isEmpty ? Colors.transparent : bg,
        elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        toolbarHeight: _tab == 0 ? 68 : kToolbarHeight,
        titleSpacing: _tab == 0 ? 8 : 16,
        leading: _tab == 2 && _profileSection != null
            ? IconButton(
                onPressed: () => setState(() => _profileSection = null),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: _tab == 0
            ? Row(
                children: [
                  Image.asset(
                    'assets/app_icon.png',
                    width: 43,
                    height: 43,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xAA292929),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onSubmitted: _onSearchChanged,
                        style: const TextStyle(color: white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search movies & series...',
                          hintStyle: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.white70,
                            size: 21,
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
                                    size: 18,
                                  ),
                                ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 13,
                            horizontal: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      _onSearchChanged(_searchController.text);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.greenAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Search',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                _pageTitle(),
                style: const TextStyle(
                  color: gold,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontFamily: 'sans-serif-rounded',
                ),
              ),
        actions: _tab == 0
            ? const []
            : [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Tooltip(
                    message: _online
                        ? 'Internet connected'
                        : 'No internet connection',
                    child: Icon(
                      _online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: _online ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ),
              ],
      ),
      body: !_connectionKnown
          ? const Center(
              child: CircularProgressIndicator(color: gold),
            )
          : (_tab == 0 && !_online && _allMovies().isEmpty)
              ? const NoInternetScreen()
              : _currentPage(),
      extendBody: true,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xCC17181D),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: const Color(0x3322DCA0),
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          FocusScope.of(context).unfocus();
          setState(() {
            _search = '';
            _searchController.clear();
            _searchLoading = false;
            _profileSection = null;
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
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Me',
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
  final VoidCallback onShare;
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
    required this.onShare,
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
                              movie.mediaType == 'tv' ? 'TV SERIES' : 'MOVIE',
                              style: const TextStyle(
                                color: gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
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
                            if (movie.originCountry.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Country: ${movie.originCountry}',
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ],
                            if (movie.originalLanguage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Language: ${movie.originalLanguage.toUpperCase()}',
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ],
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
                  if (movie.hasPlayableVideoUrl)
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
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'This title is not currently available to stream on FLIXORA.',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.playlist_add, color: gold),
                          label: const Text('Add to list', style: TextStyle(color: white)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onShare,
                          icon: const Icon(Icons.share_outlined, color: gold),
                          label: const Text('Share', style: TextStyle(color: white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
  final List<Movie> recommendedMovies;
  final ValueChanged<Movie>? onMovieSelected;
  final VoidCallback? onSave;
  final VoidCallback? onDownload;
  final VoidCallback? onViewDownloads;
  final bool isOnline;

  const MoviePlayerScreen({
    super.key,
    required this.movie,
    this.localFilePath,
    this.recommendedMovies = const [],
    this.onMovieSelected,
    this.onSave,
    this.onDownload,
    this.onViewDownloads,
    this.isOnline = true,
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
  bool _playerIsOnline = true;
  Timer? _playerConnectionTimer;
  List<Map<String, String>> _availableQualities = [];
  String? _selectedQuality;
  String _currentVideoUrl = '';
  bool _loadingQualities = false;
  int _selectedAudioTrackIndex = 0;

  String? _errorMessage;

  double _speed = 1.0;
  double _volume = 100;
  double _screenBrightness = 0.5;

  double _videoZoom = 1.0;
  String? _gestureMode;
  String _gestureFeedback = '';
  Offset? _gestureStartPoint;
  Duration _gestureStartPosition = Duration.zero;
  Duration? _gesturePreviewPosition;
  double _gestureStartBrightness = 0.5;
  double _gestureStartVolume = 100;
  double _gestureStartZoom = 1.0;
  Timer? _gestureFeedbackTimer;

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

  String _resolveInitialNetworkUrl() {
    // Admin-managed encodes take priority over the legacy single video_url.
    // This keeps the initial source and the quality selector in sync.
    if (_availableQualities.isNotEmpty) {
      final defaultQuality = _availableQualities
          .cast<Map<String, String>?>()
          .firstWhere(
            (item) => item?['quality']?.trim().toLowerCase() == '720p',
            orElse: () => _availableQualities.first,
          )!;
      _selectedQuality = defaultQuality['quality'];
      return defaultQuality['video_url'] ?? '';
    }

    final legacyUrl = widget.movie.videoUrl.trim();
    final legacyUri = Uri.tryParse(legacyUrl);
    if (legacyUri != null &&
        (legacyUri.scheme == 'http' || legacyUri.scheme == 'https') &&
        legacyUri.host.isNotEmpty) {
      return legacyUrl;
    }
    return '';
  }

  bool get _validVideoUrl {
    if (widget.localFilePath != null) return true;
    final url = _resolveInitialNetworkUrl();
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();

    _playerIsOnline = widget.isOnline;
    _player = Player();
    _videoController = VideoController(_player);

    _attachPlayerListeners();
    _loadApplicationBrightness();
    _startPlayerConnectionMonitor();
    _prepareAndInitializePlayer();
  }

  Future<void> _prepareAndInitializePlayer() async {
    // Load Admin quality URLs before opening the player. This allows playback
    // even when the legacy movies.video_url field is empty.
    await _loadVideoQualities();
    if (!mounted || _isDisposed) return;
    await _initializePlayer();
  }

  Future<void> _loadVideoQualities() async {
    final client = supabaseClient;
    final movieId = widget.movie.sourceId;
    if (client == null || movieId <= 0 || widget.localFilePath != null) return;

    if (mounted) setState(() => _loadingQualities = true);
    try {
      final rows = await client
          .from('movie_video_qualities')
          .select('quality, video_url')
          .eq('movie_id', movieId);

      final qualities = (rows as List)
          .whereType<Map>()
          .map((row) => {
                'quality': (row['quality'] ?? '').toString(),
                'video_url': (row['video_url'] ?? '').toString(),
              })
          .where((row) =>
              row['quality']!.isNotEmpty && row['video_url']!.isNotEmpty)
          .toList();

      final sortedQualities = VideoQualityService.sort(
        qualities, (item) => item['quality']!,
      );

      if (!mounted || _isDisposed) return;
      setState(() {
        _availableQualities = sortedQualities;
        if (sortedQualities.isNotEmpty) {
          final current = sortedQualities.where(
            (item) => item['video_url'] == widget.movie.videoUrl,
          );
          _selectedQuality = current.isNotEmpty
              ? current.first['quality']
              : null;
        }
      });
    } catch (e) {
      debugPrint('Could not load video qualities: $e');
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _loadingQualities = false);
      }
    }
  }

  Future<void> _changeVideoQuality(Map<String, String> item) async {
    final url = item['video_url']?.trim() ?? '';
    if (url.isEmpty || _isDisposed || widget.localFilePath != null) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return;
    }

    if (_isOpening || url == _currentVideoUrl) return;

    final previousQuality = _selectedQuality;
    final previousUrl = _currentVideoUrl;
    final wasPlaying = _isPlaying;
    final resumeAt = _position;
    _isOpening = true;

    try {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _initialized = false;
        });
      }

      await _player.open(Media(url));
      if (!mounted || _isDisposed) return;
      if (resumeAt > Duration.zero) await _player.seek(resumeAt);
      if (wasPlaying) {
        await _player.play();
      } else {
        await _player.pause();
      }

      _currentVideoUrl = url;
      if (mounted && !_isDisposed) {
        setState(() {
          _selectedQuality = item['quality'];
          _initialized = true;
        });
      }
    } catch (e) {
      // Re-open the previous encoded URL so a failed quality change does not
      // leave the player stuck on a broken source.
      var restored = false;
      if (previousUrl.isNotEmpty && !_isDisposed) {
        try {
          await _player.open(Media(previousUrl));
          if (resumeAt > Duration.zero) await _player.seek(resumeAt);
          if (wasPlaying) {
            await _player.play();
          } else {
            await _player.pause();
          }
          _currentVideoUrl = previousUrl;
          restored = true;
        } catch (_) {
          restored = false;
        }
      }

      if (mounted && !_isDisposed) {
        setState(() {
          _selectedQuality = previousQuality;
          _initialized = restored;
          _errorMessage = restored
              ? 'Could not switch quality. Previous playback was restored.'
              : 'Could not switch quality or restore the previous video.';
        });
      }
    } finally {
      _isOpening = false;
    }
  }

  void _startPlayerConnectionMonitor() {
    _refreshPlayerConnection();
    _playerConnectionTimer?.cancel();
    _playerConnectionTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshPlayerConnection(),
    );
  }

  Future<void> _refreshPlayerConnection() async {
    if (!mounted || _isDisposed) return;

    final online = await InternetService.isOnline();
    if (!mounted || _isDisposed || online == _playerIsOnline) return;

    setState(() => _playerIsOnline = online);
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
      setState(() {
        _tracks = value;
        if (_selectedAudioTrackIndex >= value.audio.length) {
          _selectedAudioTrackIndex = 0;
        }
      });
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

      if (widget.localFilePath != null &&
          !await File(widget.localFilePath!).exists()) {
        throw Exception('Downloaded file is missing.');
      }
      final playbackSource = widget.localFilePath ?? _resolveInitialNetworkUrl();
      if (playbackSource.trim().isEmpty) {
        throw Exception('No playable video URL is available.');
      }
      await _player.open(Media(playbackSource));
      if (widget.localFilePath == null) {
        _currentVideoUrl = playbackSource;
      }

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

  void _handlePlayerGestureStart(ScaleStartDetails details) {
    _gestureFeedbackTimer?.cancel();
    _gestureStartPoint = details.localFocalPoint;
    _gestureStartPosition = _position;
    _gestureStartBrightness = _screenBrightness;
    _gestureStartVolume = _volume;
    _gestureStartZoom = _videoZoom;
    _gestureMode = null;
    _gesturePreviewPosition = null;
  }

  void _handlePlayerGestureUpdate(ScaleUpdateDetails details) {
    if (!_initialized || _isLocked || _errorMessage != null) return;

    // Two-finger pinch controls video zoom without changing the stream.
    if (details.pointerCount >= 2) {
      if (_gestureMode != 'zoom') {
        _cancelHideTimer();
        setState(() {
          _gestureMode = 'zoom';
        });
      }

      final nextZoom =
          (_gestureStartZoom * details.scale).clamp(1.0, 3.0).toDouble();
      if ((nextZoom - _videoZoom).abs() > 0.005) {
        setState(() {
          _videoZoom = nextZoom;
          _gestureFeedback = '${(nextZoom * 100).round()}%';
        });
      }
      return;
    }

    // Once a pinch has started, lifting one finger must not turn it into a
    // brightness, volume, or seek gesture.
    if (_gestureMode == 'zoom') return;

    final start = _gestureStartPoint;
    if (start == null) return;

    final delta = details.localFocalPoint - start;
    if (_gestureMode == null) {
      if (delta.distance < 10) return;

      final mode = delta.dx.abs() >= delta.dy.abs()
          ? 'seek'
          : (start.dx < MediaQuery.of(context).size.width / 2
              ? 'brightness'
              : 'volume');

      _cancelHideTimer();
      setState(() {
        _gestureMode = mode;
      });
    }

    if (_gestureMode == 'seek') {
      if (_duration.inMilliseconds <= 0) return;

      // A full player-width drag represents up to two minutes of seeking.
      final width = MediaQuery.of(context).size.width;
      final secondsDelta = (delta.dx / width * 120).round();
      final targetMilliseconds = (_gestureStartPosition.inMilliseconds +
              (delta.dx / width * 120000).round())
          .clamp(0, _duration.inMilliseconds)
          .toInt();

      setState(() {
        _gesturePreviewPosition =
            Duration(milliseconds: targetMilliseconds);
        _gestureFeedback =
            '${secondsDelta >= 0 ? '+' : ''}${secondsDelta}s';
      });
    } else if (_gestureMode == 'brightness') {
      final height = MediaQuery.of(context).size.height;
      final brightness = (_gestureStartBrightness - delta.dy / height)
          .clamp(0.0, 1.0)
          .toDouble();
      _changeApplicationBrightness(brightness);
      if (mounted && !_isDisposed) {
        setState(() {
          _gestureFeedback = '${(brightness * 100).round()}%';
        });
      }
    } else if (_gestureMode == 'volume') {
      final height = MediaQuery.of(context).size.height;
      final volume = (_gestureStartVolume - delta.dy / height * 100)
          .clamp(0.0, 100.0)
          .toDouble();
      _changeVolume(volume);
      if (mounted && !_isDisposed) {
        setState(() {
          _gestureFeedback = '${volume.round()}%';
        });
      }
    }
  }

  Future<void> _handlePlayerGestureEnd(ScaleEndDetails details) async {
    final mode = _gestureMode;
    final previewPosition = _gesturePreviewPosition;

    if (mode == 'seek' && previewPosition != null) {
      await _player.seek(previewPosition);
      if (mounted && !_isDisposed) {
        setState(() {
          _position = previewPosition;
        });
      }
    }

    _gestureStartPoint = null;
    _gestureFeedbackTimer?.cancel();

    if (!mounted || _isDisposed) return;
    _gestureFeedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted || _isDisposed) return;
      setState(() {
        _gestureMode = null;
        _gestureFeedback = '';
        _gesturePreviewPosition = null;
      });
    });
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

  Future<void> _selectAudioTrack(
    AudioTrack track, {bool closeSheet = true}
  ) async {
    try {
      await _player.setAudioTrack(track);
      if (!mounted) return;
      final index = _tracks.audio.indexOf(track);
      setState(() => _selectedAudioTrackIndex = index < 0 ? 0 : index);
      if (closeSheet) Navigator.pop(context);
      _startHideTimer();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change audio language: $error')),
        );
      }
    }
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

  Future<void> _loadApplicationBrightness() async {
    try {
      final value = await ScreenBrightness.instance.application;
      if (!mounted || _isDisposed) return;
      setState(() {
        _screenBrightness = value.clamp(0.0, 1.0).toDouble();
      });
    } catch (e) {
      debugPrint('Could not read app brightness: $e');
    }
  }

  Future<void> _changeApplicationBrightness(double value) async {
    final brightness = value.clamp(0.0, 1.0).toDouble();
    if (mounted && !_isDisposed) {
      setState(() => _screenBrightness = brightness);
    }
    try {
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(brightness);
    } catch (e) {
      debugPrint('Could not change app brightness: $e');
    }
  }

  Future<void> _resetApplicationBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('Could not reset app brightness: $e');
    }
  }

  Future<void> _showQualitySelector() async {
    if (_availableQualities.isEmpty || _loadingQualities) return;
    _cancelHideTimer();

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select video quality',
                style: TextStyle(
                  color: white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Changes the encoded resolution of this same movie.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableQualities.map((item) {
                  final quality = item['quality']!;
                  final active = quality == _selectedQuality;
                  final label = VideoQualityService.displayName(quality);
                  return ChoiceChip(
                    label: Text(label),
                    selected: active,
                    selectedColor: gold,
                    backgroundColor: bg,
                    labelStyle: TextStyle(
                      color: active ? Colors.black : white,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => Navigator.pop(sheetContext, item),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || _isDisposed) return;
    if (selected != null && selected['quality'] != _selectedQuality) {
      await _changeVideoQuality(selected);
    }
    _startHideTimer();
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

        // Keep the modal slider state independent for immediate drag feedback.
        double sheetBrightness =
            _screenBrightness.clamp(0.0, 1.0).toDouble();

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
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
                    Row(
                      children: [
                        const Icon(Icons.brightness_6_outlined, color: gold, size: 20),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'Screen Brightness',
                            style: TextStyle(color: white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: gold.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            '${(sheetBrightness * 100).round()}%',
                            style: const TextStyle(
                              color: goldLight,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderTheme.of(sheetContext).copyWith(
                        trackHeight: 4,
                        activeTrackColor: gold,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: gold.withValues(alpha: 0.18),
                        showValueIndicator: ShowValueIndicator.never,
                        trackShape: const RoundedRectSliderTrackShape(),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: sheetBrightness,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (value) {
                          final nextBrightness =
                              value.clamp(0.0, 1.0).toDouble();

                          // Update the thumb, active track, and percentage immediately.
                          setSheetState(() {
                            sheetBrightness = nextBrightness;
                          });

                          // Apply the selected value to the actual app brightness.
                          _changeApplicationBrightness(nextBrightness);
                        },
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dim', style: TextStyle(color: Colors.white54, fontSize: 11)),
                        Text('Bright', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 14),
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

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
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
                        Navigator.pop(sheetContext);
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
                        Navigator.pop(sheetContext);
                        _showSubtitleTracks();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
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
      padding: const EdgeInsets.fromLTRB(18, 0, 66, 18),
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
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    activeTrackColor: gold,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: white,
                    overlayColor: gold.withValues(alpha: 0.16),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5.5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: current,
                    min: 0,
                    max: max > 0 ? max : 1,
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
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 40,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => _changeVolume(_volume - 10),
                icon: const Icon(
                  Icons.volume_down,
                  color: white,
                  size: 20,
                ),
              ),
              SizedBox(
                width: 52,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: gold,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: gold.withValues(alpha: 0.16),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: _volume.clamp(0.0, 100.0),
                    min: 0,
                    max: 100,
                    onChanged: _changeVolume,
                  ),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 40,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => _changeVolume(_volume + 10),
                icon: const Icon(
                  Icons.volume_up,
                  color: white,
                  size: 20,
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
            onPressed: () {
              if (_isFullscreen) {
                _toggleFullscreen();
              } else {
                Navigator.pop(context);
              }
            },
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
          if (widget.localFilePath == null) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: white,
                side: BorderSide(
                  color: _availableQualities.isNotEmpty ? gold : Colors.white30,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _availableQualities.isNotEmpty
                  ? _showQualitySelector
                  : null,
              icon: const Icon(Icons.high_quality, size: 17),
              label: Text(
                _loadingQualities
                    ? '...'
                    : _selectedQuality == null
                        ? 'Quality'
                        : VideoQualityService.displayName(_selectedQuality!),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
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
          child: ClipRect(
            child: Transform.scale(
              scale: _videoZoom,
              child: Video(
                controller: _videoController,
                fit: BoxFit.contain,
                controls: NoVideoControls,
              ),
            ),
          ),
        ),
        if ((_isBuffering || !_initialized) && _errorMessage == null)
          const IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: gold,
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ),
        if (_errorMessage != null)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              child: _playerError(),
            ),
          ),
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
              onScaleStart: _handlePlayerGestureStart,
              onScaleUpdate: _handlePlayerGestureUpdate,
              onScaleEnd: _handlePlayerGestureEnd,
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
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
          ),
        if (_showControls && !_isLocked && _errorMessage == null)
          Positioned(
            right: 10,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: IconButton(
                tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: _toggleFullscreen,
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: white,
                ),
              ),
            ),
          ),
        if (_gestureMode != null && _gestureFeedback.isNotEmpty && !_isLocked)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: gold.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _gestureMode == 'brightness'
                            ? Icons.brightness_6
                            : _gestureMode == 'volume'
                                ? Icons.volume_up
                                : _gestureMode == 'zoom'
                                    ? Icons.zoom_in
                                    : (_gestureFeedback.startsWith('-')
                                        ? Icons.fast_rewind
                                        : Icons.fast_forward),
                        color: gold,
                        size: 25,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _gestureMode == 'seek' &&
                                _gesturePreviewPosition != null
                            ? '${_formatDuration(_gesturePreviewPosition!)}  ($_gestureFeedback)'
                            : _gestureMode == 'brightness'
                                ? 'Brightness  $_gestureFeedback'
                                : _gestureMode == 'volume'
                                    ? 'Volume  $_gestureFeedback'
                                    : 'Zoom  $_gestureFeedback',
                        style: const TextStyle(
                          color: white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    // Persist the latest playback position even if the position stream has
    // not emitted its final update yet when the user leaves the player.
    unawaited(_saveResumePosition(_position));
    _isDisposed = true;
    _gestureFeedbackTimer?.cancel();
    _playerConnectionTimer?.cancel();
    unawaited(_resetApplicationBrightness());
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

  List<Movie> get _relatedMovies {
    final candidates = widget.recommendedMovies
        .where((item) =>
            item.id != widget.movie.id &&
            item.genres.any(widget.movie.genres.contains))
        .toList();
    candidates.sort((a, b) {
      final aMatches = a.genres.where(widget.movie.genres.contains).length;
      final bMatches = b.genres.where(widget.movie.genres.contains).length;
      return bMatches.compareTo(aMatches);
    });
    return candidates.take(20).toList();
  }

  List<Movie> get _otherMovies => widget.recommendedMovies
      .where((item) => item.id != widget.movie.id)
      .toList();

  List<Movie> get _recommendedMovies {
    final relatedIds = _relatedMovies.map((movie) => movie.id).toSet();
    return _otherMovies
        .where((item) => !relatedIds.contains(item.id))
        .take(20)
        .toList();
  }

  List<Movie> _sortedMovies(Iterable<Movie> movies, int Function(Movie, Movie) compare) {
    final result = movies.toList();
    result.sort(compare);
    return result;
  }

  Widget _movieRail(String title, List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: const TextStyle(
                color: white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 188,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (context, index) {
                final item = movies[index];
                return GestureDetector(
                  onTap: widget.onMovieSelected == null
                      ? null
                      : () => widget.onMovieSelected!(item),
                  child: SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                            width: 112,
                            height: 148,
                            child: item.posterUrl.isNotEmpty
                                ? FlixoraCachedImage(
                                    isOnline: _playerIsOnline,
                                    imageUrl: item.posterUrl,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: panel,
                                    child: const Icon(
                                      Icons.movie,
                                      color: gold,
                                      size: 35,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailAction(IconData icon, String label, VoidCallback? onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: white,
        side: const BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      icon: Icon(icon, color: gold, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _audioTrackLabel(AudioTrack track, int index) {
    final title = track.title?.trim() ?? '';
    final language = track.language?.trim() ?? '';
    if (title.isNotEmpty) return title;
    const languageNames = <String, String>{
      'en': 'English', 'eng': 'English',
      'hi': 'Hindi', 'hin': 'Hindi',
      'bn': 'Bengali', 'ben': 'Bengali',
      'ta': 'Tamil', 'tam': 'Tamil',
      'te': 'Telugu', 'tel': 'Telugu',
      'kn': 'Kannada', 'kan': 'Kannada',
      'ml': 'Malayalam', 'mal': 'Malayalam',
      'ja': 'Japanese', 'jpn': 'Japanese',
      'ko': 'Korean', 'kor': 'Korean',
      'zh': 'Chinese', 'zho': 'Chinese',
      'es': 'Spanish', 'spa': 'Spanish',
      'fr': 'French', 'fra': 'French',
    };
    if (language.isNotEmpty) {
      return languageNames[language.toLowerCase()] ?? language;
    }
    return index == 0 ? 'Original / Auto' : 'Audio ${index + 1}';
  }

  Widget _playerResources() {
    if (_tracks.audio.isEmpty) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.language, color: gold),
        title: Text('Resources',
            style: TextStyle(color: white, fontWeight: FontWeight.bold)),
        subtitle: Text('No alternate audio languages are available.',
            style: TextStyle(color: Colors.white60)),
      );
    }
    final selectedIndex = _selectedAudioTrackIndex
        .clamp(0, _tracks.audio.length - 1).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resources', style: TextStyle(
                    color: white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Select audio language', style: TextStyle(
                    color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          DropdownButton<int>(
            value: selectedIndex,
            dropdownColor: panel,
            style: const TextStyle(color: white),
            underline: Container(height: 1, color: gold),
            items: _tracks.audio.asMap().entries.map((entry) =>
              DropdownMenuItem<int>(
                value: entry.key,
                child: Text(_audioTrackLabel(entry.value, entry.key)),
              ),
            ).toList(),
            onChanged: (index) {
              if (index == null || index < 0 || index >= _tracks.audio.length) {
                return;
              }
              _selectAudioTrack(_tracks.audio[index], closeSheet: false);
            },
          ),
        ],
      ),
    );
  }

  Widget _playerPageContent() {
    final related = _relatedMovies;
    final recommended = _recommendedMovies;
    final allSuggestions = _otherMovies;
    final topRated = _sortedMovies(
      allSuggestions.where((movie) => movie.rating > 0),
      (a, b) => b.rating.compareTo(a.rating),
    ).take(20).toList();
    final latest = _sortedMovies(
      allSuggestions.where((movie) => movie.year != 'N/A'),
      (a, b) => b.year.compareTo(a.year),
    ).take(20).toList();
    final actionMovies = allSuggestions
        .where((movie) => movie.genres.any((genre) =>
            genre.toLowerCase().contains('action') ||
            genre.toLowerCase().contains('adventure')))
        .take(20).toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _playerBody(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 17, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.movie.title,
                  style: const TextStyle(
                    color: white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                if (widget.movie.year.isNotEmpty)
                  Text(
                    widget.movie.year,
                    style: const TextStyle(color: Colors.white60),
                  ),
                if (widget.movie.originCountry.isNotEmpty ||
                    widget.movie.originalLanguage.isNotEmpty ||
                    widget.movie.genres.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (widget.movie.mediaType == 'tv') 'TV Series' else 'Movie',
                      if (widget.movie.originCountry.isNotEmpty) widget.movie.originCountry,
                      if (widget.movie.originalLanguage.isNotEmpty) widget.movie.originalLanguage.toUpperCase(),
                      ...widget.movie.genres.take(3),
                    ].join('  •  '),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
                if (widget.movie.overview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.movie.overview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailAction(Icons.playlist_add, 'Add to list', widget.onSave),
                    _detailAction(Icons.share_outlined, 'Share', () => Share.share(
                      '${widget.movie.title} (${widget.movie.year}) on FLIXORA',
                    )),
                    _detailAction(Icons.download_outlined, 'Download', widget.onDownload),
                    _detailAction(Icons.video_library_outlined, 'View downloads', widget.onViewDownloads),
                  ],
                ),
                const SizedBox(height: 18),
                _playerResources(),
                const SizedBox(height: 12),
                const Text(
                  'For You',
                  style: TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _movieRail('Related Movies', related)),
        SliverToBoxAdapter(child: _movieRail('Recommended for You', recommended)),
        SliverToBoxAdapter(child: _movieRail('Top Rated Movies', topRated)),
        SliverToBoxAdapter(child: _movieRail('Recently Added', latest)),
        SliverToBoxAdapter(child: _movieRail('Action & Adventure', actionMovies)),
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) {
          _toggleFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        body: _isFullscreen
            ? SafeArea(
                top: false,
                bottom: false,
                child: _playerBody(),
              )
            : SafeArea(
                top: true,
                bottom: true,
                child: _playerPageContent(),
              ),
      ),
    );
  }
}
