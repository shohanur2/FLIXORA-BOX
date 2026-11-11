import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'streaming/anilist_service.dart';
import 'streaming/episode_number_mapper.dart';
import 'streaming/provider_catalog.dart';
import 'streaming/featured_carousel_layout.dart';
import 'streaming/tmdb_media_type.dart';
import 'streaming/provider_embed_player.dart';
import 'streaming/media3_player_view.dart';
import 'streaming/ott_catalog_service.dart';
import 'streaming/external_catalog_service.dart';
import 'streaming/peertube_source_service.dart';
import 'streaming/public_domain_movie_source_service.dart';

SupabaseClient? supabaseClient;

const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY');
const String authRedirectUrl =
    'com.flixora.flixora://login-callback/';

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

// FLIXORA cinematic surfaces: deep black, white typography and warm gold.
const Color bg = Color(0xFF080808);
const Color panel = Color(0xFF181818);
const Color gold = Color(0xFFD6AD45);
const Color goldLight = Color(0xFFF2CF75);
const Color premiumGold = Color(0xFFE8C15A);
const Color white = Color(0xFFFFFFFF);
const Color ink = Color(0xFFFFFFFF);
const Color ink70 = Color(0xB3FFFFFF);
const Color ink60 = Color(0x99FFFFFF);
const Color ink58 = Color(0x94FFFFFF);
const Color ink54 = Color(0x8AFFFFFF);
const Color ink38 = Color(0x61FFFFFF);
const Color ink24 = Color(0x3DFFFFFF);
const Color ink12 = Color(0x1FFFFFFF);
const Color ink10 = Color(0x1AFFFFFF);
const Color playerBg = Color(0xFF080808);
const Color playerPanel = Color(0xFF191919);
const Color playerGold = Color(0xFFD6AD45);
const Color playerGoldLight = Color(0xFFF2CF75);
const Color playerWhite = Colors.white;

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

/// Legacy model name retained for compatibility; this represents any FLIXORA
/// catalogue title, including movies, TV shows, web series, dramas and anime.
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
  final List<String> audioLanguages;

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
    this.audioLanguages = const [],
  });

  bool get isFlixora => source == 'flixora';

  bool get hasPlayableVideoUrl {
    final uri = Uri.tryParse(videoUrl.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Movie and TV titles can use their matching provider route when no
  /// Admin-managed direct MP4/HLS source is attached.
  bool get canAttemptPlayback =>
      hasPlayableVideoUrl ||
      ((mediaType == 'movie' || mediaType == 'tv') && tmdbId > 0);

  Movie withFallbackMetadata(Movie fallback) => Movie(
        id: id,
        tmdbId: tmdbId > 0 ? tmdbId : fallback.tmdbId,
        sourceId: sourceId,
        source: source,
        title: title.trim().isNotEmpty && title != 'Unknown Title'
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
        audioLanguages: audioLanguages.isNotEmpty ? audioLanguages : fallback.audioLanguages,
      );

  factory Movie.fromJson(Map<String, dynamic> json, {String? mediaType}) {
    final date = (json['release_date'] ?? json['first_air_date'] ?? '').toString();
    final movieId = _toInt(json['id']);

    return Movie(
      id: movieId,
      tmdbId: movieId,
      title: (json['title'] ?? json['name'] ?? 'Unknown Title').toString(),
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
      title: (json['title'] ?? 'Unknown Title').toString(),
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
      mediaType: (json['media_type'] ?? 'movie').toString() == 'tv'
          ? 'tv'
          : 'movie',
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
      title: (json['title'] ?? 'Unknown Title').toString(),
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
      audioLanguages: (json['audioLanguages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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
        'audioLanguages': audioLanguages,
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
  final int? memCacheWidth;
  final int? memCacheHeight;

  const FlixoraCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    required this.isOnline,
    this.placeholder,
    this.fallback,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final empty = fallback ?? Container(color: panel);
    if (imageUrl.isEmpty) return empty;
    if (isOnline) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        useOldImageOnUrlChange: true,
        placeholder: (_, __) => placeholder ?? Container(color: panel),
        errorWidget: (_, __, ___) => empty,
      );
    }

    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(imageUrl),
      builder: (context, snapshot) {
        final file = snapshot.data?.file;
        if (file != null && file.existsSync()) {
          return Image.file(
            file,
            fit: fit,
            cacheWidth: memCacheWidth,
            cacheHeight: memCacheHeight,
          );
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
  static DateTime? _lastCheckAt;
  static bool? _lastCheckResult;
  static Future<bool>? _inFlight;

  static Future<bool> isOnline() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        _lastCheckAt = DateTime.now();
        _lastCheckResult = false;
        return false;
      }

      final now = DateTime.now();
      if (_lastCheckAt != null &&
          _lastCheckResult != null &&
          now.difference(_lastCheckAt!) < const Duration(seconds: 5)) {
        return _lastCheckResult!;
      }

      final pending = _inFlight;
      if (pending != null) return pending;

      final check = _probeInternet();
      _inFlight = check;
      try {
        final result = await check;
        _lastCheckAt = DateTime.now();
        _lastCheckResult = result;
        return result;
      } finally {
        _inFlight = null;
      }
    } catch (_) {
      _lastCheckAt = DateTime.now();
      _lastCheckResult = false;
      return false;
    }
  }

  static Future<bool> _probeInternet() async {
    final endpoints = <Uri>[
      Uri.parse('https://www.google.com/generate_204'),
      Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      Uri.parse('https://image.tmdb.org/t/p/w92/'),
      Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
    ];

    final reachable = await Future.wait<bool>(
      endpoints.map((endpoint) async {
        try {
          final response = await http
              .get(endpoint)
              .timeout(const Duration(seconds: 3));
          return response.statusCode < 500;
        } catch (_) {
          return false;
        }
      }),
    );
    return reachable.any((value) => value);
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
  static const String bollywoodMoviesKey = 'flixora_bollywood_movies';
  static const String hollywoodMoviesKey = 'flixora_hollywood_movies';
  static const String southIndianMoviesKey = 'flixora_south_indian_movies';
  static const String indianDramaTvKey = 'flixora_indian_drama_tv';

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

  /// Retries transient TMDB throttling and server errors instead of silently
  /// leaving a category with only one page of results.
  static Future<http.Response> _getWithRetry(Uri uri) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200 ||
            (response.statusCode != 429 && response.statusCode < 500) ||
            attempt == 2) {
          return response;
        }
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        final delay = retryAfter != null
            ? Duration(seconds: retryAfter.clamp(1, 5).toInt())
            : Duration(milliseconds: 400 * (attempt + 1));
        await Future.delayed(delay);
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw Exception('TMDB request failed after retries.');
  }

  static Future<List<Movie>> getMovies(
    String endpoint, {
    Map<String, String> extraParams = const {},
    int pages = 1,
  }) async {
    if (apiKey.isEmpty) throw Exception('TMDB service is not configured.');
    final isTv = TmdbMediaType.isTvEndpoint(endpoint);
    final pageCount = pages.clamp(1, 3).toInt();
    final pageResults = await Future.wait<List<Movie>>(
      List<int>.generate(pageCount, (index) => index + 1).map((page) async {
        try {
          final uri = Uri.parse('$base/$endpoint').replace(queryParameters: {
            'api_key': apiKey,
            'language': 'en-US',
            'page': page.toString(),
            ...extraParams,
          });
          final response = await _getWithRetry(uri);
          if (response.statusCode != 200) {
            debugPrint('TMDB $endpoint page $page returned ${response.statusCode}');
            return <Movie>[];
          }
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final results = data['results'] as List? ?? [];
          return results.whereType<Map>().map((item) => Movie.fromJson(
            Map<String, dynamic>.from(item), mediaType: isTv ? 'tv' : 'movie',
          )).toList();
        } catch (error) {
          debugPrint('Catalogue page $page failed for $endpoint: $error');
          return <Movie>[];
        }
      }),
    );
    return _deduplicateCataloguePages(pageResults.expand((items) => items));
  }

  static List<Movie> _deduplicateCataloguePages(Iterable<Movie> movies) {
    final seen = <String>{};
    return movies.where((movie) {
      final key = movie.tmdbId > 0
          ? '${movie.mediaType}:${movie.tmdbId}'
          : '${movie.mediaType}:${movie.id}';
      return seen.add(key);
    }).toList();
  }

  static Future<List<Movie>> search(String query) async {
    if (apiKey.isEmpty) throw Exception('TMDB service is not configured.');
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

  static Future<List<Map<String, dynamic>>> getCast(
    int id, {String mediaType = 'movie'}
  ) async {
    if (apiKey.isEmpty || id <= 0) return [];
    try {
      final uri = Uri.parse('$base/$mediaType/$id/credits').replace(
        queryParameters: {'api_key': apiKey, 'language': 'en-US'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['cast'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .take(18)
          .toList();
    } catch (e) {
      debugPrint('Could not load cast information: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> seasonDetails(int tvId, int seasonNumber) async {
    if (apiKey.isEmpty || tvId <= 0 || seasonNumber < 0) {
      throw Exception('TV season information is not available.');
    }
    final uri = Uri.parse('$base/tv/$tvId/season/$seasonNumber').replace(
      queryParameters: {'api_key': apiKey, 'language': 'en-US'},
    );
    final response = await _getWithRetry(uri);
    if (response.statusCode != 200) {
      throw Exception("Could not load this season's episodes.");
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> details(
    int id, {String mediaType = 'movie'}
  ) async {
    if (apiKey.isEmpty) throw Exception('TMDB service is not configured.');
    final uri = Uri.parse('$base/$mediaType/$id').replace(queryParameters: {
      'api_key': apiKey, 'language': 'en-US',
      'append_to_response': 'external_ids',
    });
    final response = await _getWithRetry(uri);
    if (response.statusCode != 200) throw Exception('Could not load title details.');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Explicit endpoint fallback for titles whose details response omits
  /// appended external IDs. Play4U requires the real IMDb title identifier.
  static Future<Map<String, dynamic>> externalIds(
    int id, {String mediaType = 'movie'}
  ) async {
    if (apiKey.isEmpty || id <= 0) return const <String, dynamic>{};
    final endpoint = mediaType == 'tv' ? 'tv' : 'movie';
    final uri = Uri.parse('$base/$endpoint/$id/external_ids').replace(
      queryParameters: {'api_key': apiKey},
    );
    final response = await _getWithRetry(uri);
    if (response.statusCode != 200) return const <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
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
    List<dynamic> rawRows, {
    bool includeWithoutVideo = false,
  }) async {
    final rows = rawRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final movieIds = rows
        .map((row) => _toInt(row['id']))
        .where((id) => id > 0)
        .toList();
    final qualityFallbacks = <int, Map<String, String>>{};
    final audioLanguagesByMovie = <int, List<String>>{};

    if (movieIds.isNotEmpty) {
      try {
        final audioRows = await client.from('movie_languages')
            .select('movie_id, languages(name,code)')
            .inFilter('movie_id', movieIds);
        for (final item in (audioRows as List).whereType<Map>()) {
          final row = Map<String, dynamic>.from(item);
          final movieId = _toInt(row['movie_id']);
          final rawLanguage = row['languages'];
          if (movieId <= 0 || rawLanguage is! Map) continue;
          final language = (rawLanguage['name'] ?? rawLanguage['code'] ?? '').toString().trim();
          if (language.isNotEmpty) (audioLanguagesByMovie[movieId] ??= <String>[]).add(language);
        }
      } catch (e) {
        debugPrint('Could not load movie audio languages: $e');
      }
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
      final movie = Movie.fromSupabase(row);
      return Movie(
        id: movie.id, tmdbId: movie.tmdbId, sourceId: movie.sourceId,
        source: movie.source, title: movie.title, year: movie.year,
        overview: movie.overview, poster: movie.poster, backdrop: movie.backdrop,
        rating: movie.rating, releaseDate: movie.releaseDate, genres: movie.genres,
        runtime: movie.runtime, videoUrl: movie.videoUrl, downloadUrl: movie.downloadUrl,
        mediaType: movie.mediaType, originalLanguage: movie.originalLanguage,
        originCountry: movie.originCountry,
        audioLanguages: audioLanguagesByMovie[movieId] ?? const [],
      );
    }).where((movie) =>
        movie.sourceId > 0 &&
        (movie.hasPlayableVideoUrl ||
            (includeWithoutVideo &&
                (movie.mediaType == 'movie' || movie.mediaType == 'tv') &&
                movie.tmdbId > 0))).toList();
  }

  static Future<List<Map<String, String>>> getDownloadQualities(
    Movie movie,
  ) async {
    final client = supabaseClient;
    final options = <Map<String, String>>[];

    if (client != null && movie.sourceId > 0) {
      try {
        final rows = await client
            .from('movie_video_qualities')
            .select('quality, video_url')
            .eq('movie_id', movie.sourceId);
        for (final item in (rows as List).whereType<Map>()) {
          final quality = (item['quality'] ?? '').toString().trim();
          final url = (item['video_url'] ?? '').toString().trim();
          if (quality.isEmpty || !_isHttpUrl(url)) continue;
          final path = Uri.parse(url).path.toLowerCase();
          if (path.endsWith('.m3u8') || path.endsWith('.mpd')) continue;
          options.add({'quality': quality, 'video_url': url});
        }
      } catch (e) {
        debugPrint('Could not load download quality sources: $e');
      }
    }

    if (options.isEmpty && _isHttpUrl(movie.downloadUrl)) {
      final path = Uri.parse(movie.downloadUrl).path.toLowerCase();
      if (!path.endsWith('.m3u8') && !path.endsWith('.mpd')) {
        options.add({
          'quality': 'Original',
          'video_url': movie.downloadUrl.trim(),
        });
      }
    }

    return VideoQualityService.sort(
      options,
      (item) => item['quality'] ?? 'Original',
    );
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

      return mapPlayableRows(
        client,
        response as List,
        includeWithoutVideo: true,
      );
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

      return mapPlayableRows(
        client,
        response as List,
        includeWithoutVideo: true,
      );
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
  final String quality;
  double progress;
  int bytesReceived;
  int totalBytes;
  String status;
  String? filePath;
  String? errorMessage;

  DownloadTask({
    required this.movieId,
    required this.title,
    required this.poster,
    this.videoUrl = '',
    this.quality = 'Original',
    this.progress = 0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.status = 'Waiting',
    this.filePath,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'movieId': movieId,
        'title': title,
        'poster': poster,
        'videoUrl': videoUrl,
        'quality': quality,
        'progress': progress,
        'bytesReceived': bytesReceived,
        'totalBytes': totalBytes,
        'status': status,
        'filePath': filePath,
        'errorMessage': errorMessage,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        movieId: _toInt(json['movieId']),
        title: (json['title'] ?? 'Downloaded Movie').toString(),
        poster: (json['poster'] ?? '').toString(),
        videoUrl: (json['videoUrl'] ?? '').toString(),
        quality: (json['quality'] ?? 'Original').toString(),
        progress: (json['progress'] as num?)?.toDouble() ?? 1,
        bytesReceived: _toInt(json['bytesReceived']),
        totalBytes: _toInt(json['totalBytes']),
        status: (json['status'] ?? 'Completed').toString(),
        filePath: json['filePath']?.toString(),
        errorMessage: json['errorMessage']?.toString(),
      );
}

class DownloadManager {
  static final Dio _dio = Dio();

  static String formatBytes(int bytes) {
    if (bytes <= 0) return 'Size unavailable';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  static Future<int?> getRemoteFileSize(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(headers: {'Accept-Encoding': 'identity'}),
      ).timeout(const Duration(seconds: 10));
      final length = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (length != null && length > 0) return length;
    } catch (_) {
      // Some file hosts block HEAD requests; try a one-byte range request.
    }

    final token = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Range': 'bytes=0-0',
            'Accept-Encoding': 'identity',
          },
        ),
        cancelToken: token,
      ).timeout(const Duration(seconds: 10));
      final contentRange = response.headers.value('content-range') ?? '';
      final totalMatch = RegExp(r'/([0-9]+)$').firstMatch(contentRange);
      final total = int.tryParse(totalMatch?.group(1) ?? '');
      if (total != null && total > 0) return total;
      final length = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (response.statusCode == 200 && length != null && length > 0) {
        return length;
      }
    } catch (_) {
      // The size is unavailable when the host hides its content length.
    } finally {
      token.cancel('File size check complete');
    }
    return null;
  }

  static Future<void> download({
    required String url,
    required String fileName,
    required int uniqueId,
    required void Function(int received, int total) onProgress,
    required Future<void> Function(String path) onComplete,
    required void Function(String message) onError,
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
      final extensionMatch = RegExp(
        r'\.(mp4|mkv|webm|mov|avi|m4v)$',
        caseSensitive: false,
      ).firstMatch(uri.path);
      final extension = extensionMatch?.group(0) ?? '.mp4';
      final path = '${directory.path}/${safeName}_$uniqueId$extension';

      await _dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          onProgress(received, total);
        },
      );
      await onComplete(path);
    } on DioException catch (e) {
      onError(
        e.type == DioExceptionType.cancel
            ? 'Download cancelled'
            : 'Download failed. Please try again.',
      );
    } catch (_) {
      onError('Download failed. Please try again.');
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
        fontFamily: GoogleFonts.roboto().fontFamily,
        textTheme: GoogleFonts.robotoTextTheme(
          ThemeData.dark().textTheme,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          primary: gold,
          secondary: premiumGold,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: panel,
          indicatorColor: gold.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? gold
                  : ink58,
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
  final ScrollController _featuredCardsController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _timer;
  Timer? _networkTimer;
  Timer? _searchTimer;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AuthState>? _authSubscription;

  int _slide = 0;
  int _tab = 0;
  String _ottRegion = 'BD';
  String _ottMediaFilter = 'All';
  List<OttProvider> _ottProviders = [];
  OttProvider? _selectedOttProvider;
  List<Movie> _ottProviderTitles = [];
  bool _ottProvidersLoading = false;
  bool _ottTitlesLoading = false;
  String? _ottProvidersError;
  String? _ottTitlesError;
  String _librarySection = 'My List';
  bool _showRanking = false;
  bool _searchOpen = false;
  String _searchCategory = 'All';
  bool _rankingTv = false;
  String _rankingCategory = 'Cinema';

  String _search = '';
  bool _searchLoading = false;
  String? _searchError;

  bool loading = true;
  bool _online = false;
  bool _connectionKnown = false;
  bool _refreshing = false;
  bool _checkingConnection = false;
  bool _isOpeningTitle = false;
  String? _openingTitleKey;

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
  List<Movie> bollywoodMovies = [];
  List<Movie> hollywoodMovies = [];
  List<Movie> southIndianMovies = [];
  List<Movie> indianDramaTv = [];
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

  Set<String> get _flixoraTmdbIds {
    return flixoraMovies
        .where((title) => title.tmdbId > 0)
        .map((title) => '${title.mediaType}:${title.tmdbId}')
        .toSet();
  }

  List<Movie> _withoutFlixoraDuplicates(List<Movie> titles) {
    final adminIds = _flixoraTmdbIds;
    return titles.where((title) {
      if (title.tmdbId <= 0) return true;
      return !adminIds.contains('${title.mediaType}:${title.tmdbId}');
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

  /// Keep the Home hero and Trending Movies row populated if TMDB's
  /// trending endpoint temporarily returns an empty response. Admin records
  /// stay first so they retain precedence over matching TMDB catalogue items.
  List<Movie> _homeTrendingMovies() {
    final primary = _withoutFlixoraDuplicates(trending)
        .where((title) => title.mediaType == 'movie')
        .toList();
    final candidates = <Movie>[
      ...flixoraMovies.where((title) => title.mediaType == 'movie'),
      ...primary,
    ];

    if (primary.length < 5) {
      candidates.addAll(_withoutFlixoraDuplicates(popular)
          .where((title) => title.mediaType == 'movie'));
      candidates.addAll(_withoutFlixoraDuplicates(latest)
          .where((title) => title.mediaType == 'movie'));
      candidates.addAll(_withoutFlixoraDuplicates(topRated)
          .where((title) => title.mediaType == 'movie'));
    }

    return _deduplicateMovies(candidates);
  }

  bool _isAnimeTitle(Movie title) {
    final genres = title.genres.map((genre) => genre.toLowerCase()).toSet();
    return genres.contains('anime') ||
        (genres.contains('animation') &&
            (title.originalLanguage.toLowerCase() == 'ja' ||
                title.originCountry.toUpperCase() == 'JP'));
  }

  bool _hasHindiAudio(Movie movie) {
    return movie.audioLanguages.any((language) {
      final value = language.trim().toLowerCase();
      return value == 'hi' || value.contains('hindi');
    }) || movie.originalLanguage.toLowerCase() == 'hi';
  }

  String _displayTitle(Movie movie) {
    if (_hasHindiAudio(movie) &&
        !movie.title.toLowerCase().contains('[hindi]')) {
      return '${movie.title} [Hindi]';
    }
    return movie.title;
  }

  /// TMDB does not define "Web Series" as a TV genre. Prefer titles explicitly
  /// tagged by FLIXORA Admin; if none exist yet, show the available non-anime
  /// TV catalogue instead of leaving the Home section blank.
  List<Movie> _webSeriesTitles() {
    final catalogue = _deduplicateMovies([
      ...flixoraMovies,
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...koreanDrama,
      ...bengaliTv,
      ...indianDramaTv,
    ].where((title) => title.mediaType == 'tv').toList());

    final tagged = catalogue.where((title) => title.genres.any((genre) {
      final normalized = genre.toLowerCase().replaceAll('-', ' ').trim();
      return normalized == 'web series' || normalized == 'webseries';
    })).toList();

    if (tagged.isNotEmpty) return tagged;

    final fallback = catalogue.where((title) => !_isAnimeTitle(title)).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final authClient = supabaseClient;
    if (authClient != null) {
      _authSubscription = authClient.auth.onAuthStateChange.listen(
        (_) {
          if (mounted) setState(() {});
        },
        onError: (error, stackTrace) {
          debugPrint('Auth state listener error: $error');
        },
      );
    }

    _initializeApp();
    _listenToConnectivity();
    _networkTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshConnectionStatus(),
    );

    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (!mounted || _tab != 0) return;

        final slideCount = _homeTrendingMovies().length;
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
      await Future.wait<void>([loadHome(), _loadOttProviders()]);
    } else {
      setState(() {
        loading = false;
        if (_allMovies().isEmpty) homeError = 'offline';
      });
    }  }

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
        content: Text(message, style: const TextStyle(color: ink70, height: 1.45)),
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
      MovieCache.getList(MovieCache.bollywoodMoviesKey),
      MovieCache.getList(MovieCache.hollywoodMoviesKey),
      MovieCache.getList(MovieCache.southIndianMoviesKey),
      MovieCache.getList(MovieCache.indianDramaTvKey),
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
      bollywoodMovies = results[12];
      hollywoodMovies = results[13];
      southIndianMovies = results[14];
      indianDramaTv = results[15];
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
        await Future.wait<void>([loadHome(), _loadOttProviders()]);
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
    _authSubscription?.cancel();
    _sliderController.dispose();
    _featuredCardsController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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

      // Render primary Home sections before loading every secondary catalog.
      final coreResults = await Future.wait<List<Movie>>([
        TmdbService.getMovies('trending/movie/week').catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/popular').catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/now_playing').catchError((_) => <Movie>[]),
        TmdbService.getMovies('movie/top_rated').catchError((_) => <Movie>[]),
        TmdbService.getMovies('trending/tv/week', pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('tv/popular', pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('tv/top_rated', pages: 3).catchError((_) => <Movie>[]),
        FlixoraMovieService.getPublishedMovies().catchError((_) => <Movie>[]),
      ]);

      if (!mounted) return;
      setState(() {
        trending = coreResults[0].isNotEmpty ? coreResults[0] : trending;
        popular = coreResults[1].isNotEmpty ? coreResults[1] : popular;
        latest = coreResults[2].isNotEmpty ? coreResults[2] : latest;
        topRated = coreResults[3].isNotEmpty ? coreResults[3] : topRated;
        trendingTv = coreResults[4].isNotEmpty ? coreResults[4] : trendingTv;
        popularTv = coreResults[5].isNotEmpty ? coreResults[5] : popularTv;
        topRatedTv = coreResults[6].isNotEmpty ? coreResults[6] : topRatedTv;
        flixoraMovies = coreResults[7].isNotEmpty ? coreResults[7] : flixoraMovies;

        // Admin records stay canonical and take priority over TMDB duplicates.
        final refreshedTrendingMovies = _homeTrendingMovies();
        if (refreshedTrendingMovies.isNotEmpty) {
          trending = refreshedTrendingMovies;
        }

        loading = false;
        homeError = _allMovies().isEmpty ? 'Unable to load movies.' : null;
        final visibleCount = _homeTrendingMovies().length.clamp(0, 5).toInt();
        if (visibleCount == 0 || _slide >= visibleCount) _slide = 0;
      });

      _syncFeaturedCarouselAfterDataChange();
      await Future.wait([
        MovieCache.saveList(MovieCache.trendingKey, trending),
        MovieCache.saveList(MovieCache.popularKey, popular),
        MovieCache.saveList(MovieCache.latestKey, latest),
        MovieCache.saveList(MovieCache.topRatedKey, topRated),
        MovieCache.saveList(MovieCache.trendingTvKey, trendingTv),
        MovieCache.saveList(MovieCache.popularTvKey, popularTv),
        MovieCache.saveList(MovieCache.topRatedTvKey, topRatedTv),
        MovieCache.saveList(MovieCache.flixoraKey, flixoraMovies),
      ]);

      // Secondary catalogs now fill their sections without delaying first paint.
      final secondaryResults = await Future.wait<List<Movie>>([
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_genres': '16', 'with_origin_country': 'JP',
          'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'ko', 'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'bn', 'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'bn', 'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'hi', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'en', 'with_origin_country': 'US',
          'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ta', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'te', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ml', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'kn', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_origin_country': 'IN', 'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'ja', 'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'zh', 'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'th', 'sort_by': 'popularity.desc',
        }, pages: 2).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'hi', 'sort_by': 'popularity.desc',
        }, pages: 3).catchError((_) => <Movie>[]),
      ]);

      if (!mounted) return;
      setState(() {
        if (secondaryResults[0].isNotEmpty) anime = secondaryResults[0];
        if (secondaryResults[2].isNotEmpty) bengaliMovies = secondaryResults[2];
        if (secondaryResults[3].isNotEmpty) bengaliTv = secondaryResults[3];

        final refreshedBollywood = [...secondaryResults[4], ...secondaryResults[14]];
        if (refreshedBollywood.isNotEmpty) {
          bollywoodMovies = _deduplicateMovies(refreshedBollywood);
        }
        if (secondaryResults[5].isNotEmpty) hollywoodMovies = secondaryResults[5];

        final refreshedSouthIndian = [
          ...secondaryResults[6], ...secondaryResults[7],
          ...secondaryResults[8], ...secondaryResults[9],
        ];
        if (refreshedSouthIndian.isNotEmpty) {
          southIndianMovies = _deduplicateMovies(refreshedSouthIndian);
        }

        if (secondaryResults[10].isNotEmpty) indianDramaTv = secondaryResults[10];
        final refreshedKoreanDrama = [
          ...secondaryResults[1], ...secondaryResults[11],
          ...secondaryResults[12], ...secondaryResults[13],
        ];
        if (refreshedKoreanDrama.isNotEmpty) {
          koreanDrama = _deduplicateMovies(refreshedKoreanDrama);
        }
      });

      await Future.wait([
        MovieCache.saveList(MovieCache.animeKey, anime),
        MovieCache.saveList(MovieCache.koreanKey, koreanDrama),
        MovieCache.saveList(MovieCache.bengaliMoviesKey, bengaliMovies),
        MovieCache.saveList(MovieCache.bengaliTvKey, bengaliTv),
        MovieCache.saveList(MovieCache.bollywoodMoviesKey, bollywoodMovies),
        MovieCache.saveList(MovieCache.hollywoodMoviesKey, hollywoodMovies),
        MovieCache.saveList(MovieCache.southIndianMoviesKey, southIndianMovies),
        MovieCache.saveList(MovieCache.indianDramaTvKey, indianDramaTv),
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
      ...bollywoodMovies,
      ...hollywoodMovies,
      ...southIndianMovies,
      ...indianDramaTv,
    ];

    return _deduplicateMovies(combined);
  }

  void _openSearch() {
    if (_searchOpen) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = 0;
      _showRanking = false;
      _searchOpen = true;
      _search = '';
      _searchCategory = 'All';
      searchResults = [];
      _searchError = null;
      _searchLoading = false;
      _searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchTimer?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchOpen = false;
      _search = '';
      _searchCategory = 'All';
      searchResults = [];
      _searchError = null;
      _searchLoading = false;
      _searchController.clear();
    });
  }

  List<Movie> _searchDiscoveryMovies() {
    final titles = _allMovies();
    titles.sort((a, b) {
      final rating = b.rating.compareTo(a.rating);
      return rating != 0 ? rating : b.year.compareTo(a.year);
    });
    return titles;
  }

  List<Movie> _searchSuggestions() {
    final titles = _deduplicateMovies([
      ...trending,
      ...popular,
      ...trendingTv,
      ...popularTv,
      ...flixoraMovies,
    ]);
    if (titles.isEmpty) return _searchDiscoveryMovies().take(4).toList();
    return titles.take(4).toList();
  }

  List<Movie> _filterSearchMovies(List<Movie> source, String category) {
    switch (category) {
      case 'Movies':
        return source.where((movie) => movie.mediaType == 'movie').toList();
      case 'Series':
        return source.where((movie) =>
            movie.mediaType == 'tv' && !_isAnimeTitle(movie)).toList();
      case 'Anime':
        return source.where(_isAnimeTitle).toList();
      case 'Drama':
        return source.where((movie) => movie.genres.any(
          (genre) => genre.toLowerCase().contains('drama'),
        )).toList();
      case 'Bengali':
        return source.where((movie) =>
            movie.originalLanguage.toLowerCase() == 'bn' ||
            movie.originCountry.toUpperCase().contains('BD')).toList();
      default:
        return source;
    }
  }

  List<String> _availableSearchFilters(List<Movie> source) {
    const filters = ['All', 'Movies', 'Series', 'Anime', 'Drama', 'Bengali'];
    return filters.where((filter) =>
        filter == 'All' || _filterSearchMovies(source, filter).isNotEmpty
    ).toList();
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

    final onlineNow = await InternetService.isOnline();
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
    final results = await Future.wait<List<Movie>>([      TmdbService.search(text).catchError((_) => <Movie>[]),
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
    final query = value.trim();

    if (query.isEmpty) {
      setState(() {
        _search = '';
        _searchCategory = 'All';
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }

    setState(() {
      _search = query;
      _searchCategory = 'All';
      _searchLoading = true;
      _searchError = null;
    });

    _searchTimer = Timer(
      const Duration(milliseconds: 350),
      () => searchMovies(query),
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
    final hasInternet = await InternetService.isOnline();
    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _online = false;
          _connectionKnown = true;
        });
        _showMessage('Check your internet connection');
      }
      return;
    }

    if (mounted && !_online) setState(() => _online = true);

    final existing = _downloads.where((item) => item.movieId == movie.id).toList();
    if (existing.any((item) =>
        item.status == 'Downloading' || item.status == 'Completed')) {
      _showMessage(existing.any((item) => item.status == 'Completed')
          ? 'This movie is already downloaded.'
          : 'This movie is already downloading.');
      return;
    }

    final rawOptions = await FlixoraMovieService.getDownloadQualities(movie);
    if (!mounted) return;
    if (rawOptions.isEmpty) {
      _showMessage(
        'Download source is not available for this movie. Ask Admin to add a direct video file.',
      );
      return;
    }

    final options = await Future.wait(rawOptions.map((item) async {
      final size = await DownloadManager.getRemoteFileSize(item['video_url']!);
      return <String, String>{
        ...item,
        'size_bytes': size?.toString() ?? '',
        'size_label': size == null
            ? 'File size unavailable'
            : DownloadManager.formatBytes(size),
      };
    }));

    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose Download Quality',
                  style: TextStyle(
                    color: white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = options[index];
                      final quality = item['quality'] ?? 'Original';
                      return Material(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: ink12),
                          ),
                          leading: const Icon(
                            Icons.high_quality_rounded,
                            color: goldLight,
                            size: 25,
                          ),
                          title: Text(
                            VideoQualityService.displayName(quality),
                            style: const TextStyle(
                              color: white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'File size: ${item['size_label']}',
                            style: const TextStyle(
                              color: ink70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.download_rounded,
                            color: Color(0xFF37E69A),
                          ),
                          onTap: () => Navigator.pop(sheetContext, item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || selected == null) return;
    final selectedUrl = selected['video_url'] ?? '';
    if (selectedUrl.isEmpty) {
      _showMessage('This download source is not valid.');
      return;
    }

    final expectedBytes = int.tryParse(selected['size_bytes'] ?? '') ?? 0;
    final quality = selected['quality'] ?? 'Original';
    final task = DownloadTask(
      movieId: movie.id,
      title: movie.title,
      poster: movie.posterUrl,
      videoUrl: selectedUrl,
      quality: quality,
      totalBytes: expectedBytes,
      status: 'Downloading',
    );

    setState(() => _downloads.insert(0, task));

    await DownloadManager.download(
      url: selectedUrl,
      fileName: '${movie.title}_$quality',
      uniqueId: DateTime.now().millisecondsSinceEpoch,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          task.bytesReceived = received;
          if (total > 0) task.totalBytes = total;
          if (task.totalBytes > 0) {
            task.progress = (received / task.totalBytes).clamp(0.0, 1.0);
          }
        });
      },
      onComplete: (path) async {
        final fileSize = await File(path).length();
        if (!mounted) return;
        setState(() {
          task
            ..progress = 1
            ..bytesReceived = fileSize
            ..totalBytes = fileSize
            ..status = 'Completed'
            ..filePath = path
            ..errorMessage = null;
        });
        await MovieCache.saveDownloads(_downloads);
        _showMessage('Successfully downloaded ${movie.title}.');
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          task
            ..status = 'Failed'
            ..errorMessage = message;
        });
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
        content: const Text('Are you sure you want to delete this movie?', style: TextStyle(color: ink70)),
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
          content: Text(
            message,
            style: const TextStyle(
              color: ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFF242832),
          behavior: SnackBarBehavior.floating,
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
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = 3;
      _searchOpen = false;
      _showRanking = false;
      _search = '';
      _searchController.clear();
      _searchLoading = false;
      _profileSection = null;
    });
  }

  void _openProfileSection(String section) {
    setState(() => _profileSection = section);
  }

  String _titleOpeningKey(Movie movie) {
    if (movie.tmdbId > 0) return '${movie.mediaType}:${movie.tmdbId}';
    return '${movie.mediaType}:${movie.source}:${movie.id}';
  }

  bool _beginTitleOpening(Movie movie) {
    if (!mounted || _isOpeningTitle) return false;
    _isOpeningTitle = true;
    _openingTitleKey = _titleOpeningKey(movie);
    setState(() {});
    return true;
  }

  void _endTitleOpening() {
    _isOpeningTitle = false;
    _openingTitleKey = null;
    if (mounted) setState(() {});
  }

  bool _isTitleOpening(Movie movie) =>
      _isOpeningTitle && _openingTitleKey == _titleOpeningKey(movie);

  Widget _titleOpeningOverlay(Movie movie) {
    if (!_isTitleOpening(movie)) return const SizedBox.shrink();
    return const ColoredBox(
      color: Color(0x99000000),
      child: Center(
        child: SizedBox(
          width: 25,
          height: 25,
          child: CircularProgressIndicator(color: gold, strokeWidth: 2.4),
        ),
      ),
    );
  }

  Movie? _cachedFlixoraMatch(Movie movie) {
    if (movie.tmdbId <= 0) return null;
    for (final candidate in [...flixoraMovies, ...searchResults]) {
      if (candidate.isFlixora &&
          candidate.tmdbId == movie.tmdbId &&
          candidate.mediaType == movie.mediaType) {
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
      return requested.isFlixora
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
      } else if (requested.tmdbId > 0 &&
          (requested.mediaType == 'movie' || requested.mediaType == 'tv')) {
        response = await client
            .from('movies')
            .select()
            .eq('tmdb_id', requested.tmdbId)
            .eq('media_type', requested.mediaType)
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
          includeWithoutVideo: true,
        );
        if (playable.isEmpty) return null;

        // Keep the Admin source/status, but fill missing catalogue metadata
        // from TMDB so incomplete Admin fields do not blank the details page.
        return playable.first.withFallbackMetadata(requested);
      }

      if (requested.isFlixora) return null;
      return _cachedFlixoraMatch(requested) ?? requested;
    } catch (e) {
      debugPrint('Could not resolve Admin movie record: $e');
      // Keep the already-loaded published Admin entry usable if the network
      // lookup fails; otherwise fall back to the requested TMDB catalogue item.
      return requested.isFlixora
          ? requested
          : (_cachedFlixoraMatch(requested) ?? requested);
    }
  }

  void _showNoInternetScreen() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NoInternetScreen(),
      ),
    );
  }

  Future<void> _openMovie(Movie movie) async {
    if (!_beginTitleOpening(movie)) return;
    try {
      final hasInternet = await InternetService.isOnline();
      if (!mounted) return;
      if (!hasInternet) {
        setState(() {
          _online = false;
          _connectionKnown = true;
        });
        _showNoInternetScreen();
        return;
      }
      if (!_online) setState(() => _online = true);

      final resolvedMovie = await _resolveMovieForOpening(movie);
      if (!mounted) return;

      if (resolvedMovie == null) {
        _showMessage('This title is currently unavailable.');
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
            onWatch: () => _playResolvedMovie(selectedMovie, movie),
          ),
        ),
      );
    } finally {
      _endTitleOpening();
    }
  }

  Future<void> _playMovieFromPlayer(Movie movie) async {
    await _playMovie(movie, closeCurrentPlayer: true);
  }

  Future<void> _playMovie(
    Movie movie, {
    bool closeCurrentPlayer = false,
  }) async {
    if (!_beginTitleOpening(movie)) return;
    try {
      if (closeCurrentPlayer) {
        if (!mounted) return;
        Navigator.of(context).pop();
      }

      final selectedMovie = await _resolveMovieForOpening(movie);
      if (!mounted) return;

      if (selectedMovie == null) {
        _showMessage('This title is currently unavailable.');
        return;
      }

      await _openResolvedPlayer(selectedMovie, movie);
    } finally {
      _endTitleOpening();
    }
  }

  Future<void> _playResolvedMovie(
    Movie selectedMovie,
    Movie requestedMovie,
  ) async {
    if (!_beginTitleOpening(selectedMovie)) return;
    try {
      await _openResolvedPlayer(selectedMovie, requestedMovie);
    } finally {
      _endTitleOpening();
    }
  }

  /// Opens a player for a title that has already been resolved to the
  /// canonical Admin/TMDB record. The caller owns the tap lock.
  Future<void> _openResolvedPlayer(
    Movie selectedMovie,
    Movie requestedMovie,
  ) async {
    if (!mounted) return;

    DownloadTask? downloaded;
    for (final task in _downloads) {
      final matchesMovie = task.movieId == selectedMovie.id ||
          task.movieId == requestedMovie.id ||
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
      _recordWatch(selectedMovie);
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MoviePlayerScreen(
          movie: selectedMovie,
          localFilePath: downloaded!.filePath,
          recommendedMovies: _allMovies(),
          onMovieSelected: _playMovieFromPlayer,
          onSave: () => _toggleSaved(selectedMovie),
          onDownload: () => addDownload(selectedMovie),
          onViewDownloads: _openDownloadsTab,
          isOnline: _online,
        ),
      ));
      return;
    }

    if (!selectedMovie.canAttemptPlayback) {
      _showMessage('This title has no supported FLIXORA playback source.');
      return;
    }

    final hasInternet = await InternetService.isOnline();
    if (!mounted) return;
    if (!hasInternet) {
      setState(() {
        _online = false;
        _connectionKnown = true;
      });
      _showNoInternetScreen();
      return;
    }

    if (!_online) setState(() => _online = true);
    _recordWatch(selectedMovie);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MoviePlayerScreen(
        movie: selectedMovie,
        recommendedMovies: _allMovies(),
        onMovieSelected: _playMovieFromPlayer,
        onSave: () => _toggleSaved(selectedMovie),
        onDownload: () => addDownload(selectedMovie),
        onViewDownloads: _openDownloadsTab,
        isOnline: _online,
      ),
    ));
  }

  void _openRanking([String category = 'Cinema', bool tv = false]) {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchOpen = false;
      _showRanking = true;
      _rankingTv = tv;
      _rankingCategory = category;
    });
  }

  List<String> _sectionFilterOptions(String section) {
    switch (section) {
      case 'Trending Movies':
      case 'Popular Movies':
        return const ['Cinema', 'TOP Movies', 'New Bengali', 'Bollywood', 'Hollywood', 'South Indian', 'New Release'];
      case 'Trending TV Series':
      case 'Popular TV Series':
      case 'Top Rated TV Series':
        return const [
          'All Series', 'Top Series', 'New Bengali', 'Anime',
          'Drama', 'Web Series', 'Asian Drama', 'Indian Drama',
        ];
      case 'Anime':
        return const ['Popular', 'Action', 'Adventure', 'Fantasy', 'New Release'];
      case 'Korean & Asian Drama':
        return const ['All', 'Korean', 'Chinese', 'Japanese', 'Thai'];
      case 'Bengali Movies':
      case 'Bengali TV Series':
        return const ['All', 'New', 'Popular', 'Top Rated'];
      case 'Now Playing':
        return const ['All', 'New Release', 'Action', 'Drama'];
      case 'Top Rated Movies':
        return const ['All', 'TOP Movies', 'Bollywood', 'Hollywood', 'South Indian'];
      default:
        return const [];
    }
  }

  List<Movie> _filterSectionMovies(String section, List<Movie> source, String filter) {
    final items = _deduplicateMovies(source);

    if (section.contains('TV Series')) {
      switch (filter) {
        case 'New Bengali':
          return _deduplicateMovies(bengaliTv);
        case 'Anime':
          return _deduplicateMovies([
            ...anime,
            ...flixoraMovies.where((title) => title.mediaType == 'tv' &&
                title.genres.any((genre) => genre.toLowerCase() == 'anime')),
          ]);
        case 'Asian Drama':
          return _deduplicateMovies(koreanDrama);
        case 'Indian Drama':
          return _deduplicateMovies(indianDramaTv);
        case 'Top Series':
          final series = _deduplicateMovies([
            ...topRatedTv, ...popularTv, ...trendingTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ]);
          return series..sort((a, b) => b.rating.compareTo(a.rating));
        case 'Drama':
          return items.where((title) => title.genres.any(
            (genre) => genre.toLowerCase().contains('drama'),
          )).toList();
        case 'Web Series':
          return _webSeriesTitles();
      }
    }
    if (filter == 'All' || filter == 'Cinema' || filter == 'All Series' || filter == 'Popular') {
      if (filter == 'Popular' && section == 'Anime') {
        return items.toList()..sort((a, b) => b.rating.compareTo(a.rating));
      }
      return items;
    }
    if (filter == 'TOP Movies' || filter == 'Top Series' || filter == 'Top Rated') {
      return items.toList()..sort((a, b) => b.rating.compareTo(a.rating));
    }
    if (filter == 'New Release' || filter == 'New') {
      return items.toList()..sort((a, b) => b.year.compareTo(a.year));
    }
    if (filter == 'New Bengali') return _deduplicateMovies(bengaliMovies);
    if (filter == 'Bollywood') return _deduplicateMovies(bollywoodMovies);
    if (filter == 'Hollywood') return _deduplicateMovies(hollywoodMovies);
    if (filter == 'South Indian') return _deduplicateMovies(southIndianMovies);
    if (filter == 'Anime') {
      return items.where((m) => m.genres.any((g) => g.toLowerCase().contains('animation')) || m.originalLanguage.toLowerCase() == 'ja').toList();
    }
    if (filter == 'Asian Drama') {
      return items.where((m) => ['ko', 'zh', 'ja', 'th'].contains(m.originalLanguage.toLowerCase())).toList();
    }
    if (filter == 'Indian Drama') {
      return items.where((m) => ['hi', 'bn', 'ta', 'te', 'ml', 'kn'].contains(m.originalLanguage.toLowerCase())).toList();
    }
    if (filter == 'Korean') return items.where((m) => m.originalLanguage.toLowerCase() == 'ko').toList();
    if (filter == 'Chinese') return items.where((m) => ['zh', 'cn'].contains(m.originalLanguage.toLowerCase())).toList();
    if (filter == 'Japanese') return items.where((m) => m.originalLanguage.toLowerCase() == 'ja').toList();
    if (filter == 'Thai') return items.where((m) => m.originalLanguage.toLowerCase() == 'th').toList();
    if (filter == 'Action' || filter == 'Adventure' || filter == 'Fantasy' || filter == 'Drama') {
      return items.where((m) => m.genres.any((g) => g.toLowerCase().contains(filter.toLowerCase()))).toList();
    }
    return items;
  }

  Widget _sectionBlock(String title, List<Movie> movies) {
    final allFilters = _sectionFilterOptions(title);
    final filters = allFilters.where((filter) =>
        _filterSectionMovies(title, movies, filter).isNotEmpty).toList();
    final selected = filters.contains(_sectionFilters[title])
        ? _sectionFilters[title]!
        : (filters.isNotEmpty ? filters.first : '');
    final visibleMovies = filters.isEmpty
        ? _deduplicateMovies(movies)
        : _filterSectionMovies(title, movies, selected);

    // A category with no matching catalogue items is omitted instead of
    // leaving an empty strip on the Home page.
    if (visibleMovies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 21, 12, 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final isTvSection = title.contains('TV') ||
                      title == 'Anime' || title == 'Drama' ||
                      title == 'Web Series' || title == 'Korean & Asian Drama';
                  _openRanking(
                    isTvSection ? 'All Series' : 'Cinema',
                    isTvSection,
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: gold,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'All',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        if (filters.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final value = filters[index];
                final active = selected == value;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _sectionFilters[title] = value),
                  child: Center(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: active ? gold : ink60,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        _movieRow(visibleMovies),
      ],
    );
  }

  Widget _movieRow(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 205,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          final hasHindi = _hasHindiAudio(movie);
          return Container(
            width: 110,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF17181C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF292B31), width: 0.8),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _isOpeningTitle ? null : () => _playMovie(movie),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(7),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            movie.posterUrl.isEmpty
                                ? Container(
                                    color: panel,
                                    child: const Icon(Icons.movie, color: gold, size: 32),
                                  )
                                : FlixoraCachedImage(
                                    imageUrl: movie.posterUrl,
                                    isOnline: _online,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 330,
                                    memCacheHeight: 450,
                                    placeholder: Container(color: panel),
                                    fallback: Container(
                                      color: panel,
                                      child: const Icon(Icons.movie, color: gold),
                                    ),
                                  ),
                            if (hasHindi)
                              Positioned(
                                top: 5,
                                right: 5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xDD111216),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Hindi',
                                    style: TextStyle(
                                      color: white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      height: 39,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: const BoxDecoration(
                        color: Color(0xFF202126),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(7),
                        ),
                      ),
                      child: Text(
                        _displayTitle(movie),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
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
  void _scrollFeaturedCardTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_featuredCardsController.hasClients) return;
      final position = _featuredCardsController.position;
      if (!position.hasContentDimensions) return;
      final target = FeaturedCarouselLayout.targetScrollOffset(
        index: index,
        viewportWidth: position.viewportDimension,
        maxScrollExtent: position.maxScrollExtent,
      );
      if ((position.pixels - target).abs() < 1) return;
      _featuredCardsController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _syncFeaturedCarouselAfterDataChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visibleCount = _homeTrendingMovies().take(5).length;
      if (visibleCount == 0) {
        if (_sliderController.hasClients) _sliderController.jumpToPage(0);
        if (_featuredCardsController.hasClients) _featuredCardsController.jumpTo(0);
        return;
      }
      final currentPage = _sliderController.hasClients
          ? (_sliderController.page?.round() ?? 0)
          : 0;
      if (currentPage >= visibleCount) {
        if (_slide != 0) setState(() => _slide = 0);
        if (_sliderController.hasClients) _sliderController.jumpToPage(0);
        if (_featuredCardsController.hasClients) _featuredCardsController.jumpTo(0);
        return;
      }
      final selectedIndex = _slide.clamp(0, visibleCount - 1).toInt();
      if (selectedIndex != _slide) setState(() => _slide = selectedIndex);
      _scrollFeaturedCardTo(selectedIndex);
    });
  }

  Widget _featuredSlider() {
    final slides = _homeTrendingMovies().take(5).toList(growable: false);

    if (slides.isEmpty) {
      return const SizedBox(height: 12);
    }

    // Match the supplied mobile reference: a full-width 16:9 hero with
    // a compact, overlapping horizontal poster-card strip at its bottom.
    final heroHeight = (MediaQuery.of(context).size.width * 9 / 16)
        .clamp(200.0, 360.0)
        .toDouble();

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _sliderController,
            itemCount: slides.length,
            onPageChanged: (index) {
              if (_slide != index && mounted) {
                setState(() => _slide = index);
              }
              _scrollFeaturedCardTo(index);
            },
            itemBuilder: (context, index) {
              final movie = slides[index];
              return GestureDetector(
                onTap: _isOpeningTitle ? null : () => _playMovie(movie),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    movie.backdropUrl.isEmpty
                        ? Container(color: panel)
                        : FlixoraCachedImage(
                            imageUrl: movie.backdropUrl,
                            isOnline: _online,
                            fit: BoxFit.cover,
                            placeholder: Container(color: panel),
                            fallback: Container(color: panel),
                          ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x55000000),
                            Color(0x08000000),
                            Colors.transparent,
                            Color(0xFF080808),
                          ],
                          stops: [0, 0.28, 0.58, 1],
                        ),
                      ),
                    ),
                    _titleOpeningOverlay(movie),
                  ],
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: _featuredQuickCards(slides),
          ),
        ],
      ),
    );
  }

  Widget _featuredQuickCards(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: FeaturedCarouselLayout.cardHeight,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.axis == Axis.horizontal &&
              _sliderController.hasClients) {
            final selected = FeaturedCarouselLayout.indexForScrollOffset(
              pixels: notification.metrics.pixels,
              viewportWidth: notification.metrics.viewportDimension,
              itemCount: movies.length,
            );
            if (selected != _slide) {
              _sliderController.animateToPage(
                selected,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOut,
              );
            }
          }
          return false;
        },
        child: ListView.builder(
          controller: _featuredCardsController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: FeaturedCarouselLayout.horizontalPadding,
          ),
          itemCount: movies.length,
          itemBuilder: (context, index) {
            final movie = movies[index];
            final isAnime = movie.genres.any(
                  (genre) => genre.toLowerCase().contains('animation'),
                ) ||
                movie.originalLanguage.toLowerCase() == 'ja';
            final typeLabel = movie.mediaType == 'tv'
                ? 'TV'
                : (isAnime ? 'Anime' : 'Movie');
            final hasHindiAudio = movie.audioLanguages.any((language) {
                  final value = language.trim().toLowerCase();
                  return value == 'hi' || value.contains('hindi');
                }) ||
                movie.originalLanguage.toLowerCase() == 'hi';
            final displayTitle = hasHindiAudio &&
                    !movie.title.toLowerCase().contains('[hindi]')
                ? '${movie.title} [Hindi]'
                : movie.title;
            final yearLabel = movie.year.isNotEmpty && movie.year != 'N/A'
                ? movie.year
                : (movie.releaseDate.length >= 4
                    ? movie.releaseDate.substring(0, 4)
                    : '');
            final genreLabel =
                movie.genres.isNotEmpty ? movie.genres.first : typeLabel;
            final metadataLabel = <String>[
              if (yearLabel.isNotEmpty) yearLabel,
              if (genreLabel.isNotEmpty) genreLabel,
            ].join(' | ');

            return GestureDetector(
              onTap: _isOpeningTitle ? null : () => _playMovie(movie),
              child: Container(
                width: FeaturedCarouselLayout.cardWidth,
                margin: const EdgeInsets.symmetric(
                  horizontal: FeaturedCarouselLayout.cardMargin,
                ),
                child: SizedBox(
                  height: FeaturedCarouselLayout.cardHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: FeaturedCarouselLayout.cardTopInset,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.only(
                            left: FeaturedCarouselLayout.textLeftInset,
                            right: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25272D),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          movie.mediaType == 'tv'
                                              ? Icons.live_tv_rounded
                                              : Icons.movie_outlined,
                                          color: ink60,
                                          size: 11,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            metadataLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: ink60,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              IconButton(
                                onPressed: _isOpeningTitle
                                    ? null
                                    : () => _playMovie(movie),
                                tooltip: 'Play ${movie.title}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 34,
                                ),
                                icon: const CircleAvatar(
                                  radius: 15,
                                  backgroundColor: gold,
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Color(0xFF151515),
                                    size: 21,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        top: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: FeaturedCarouselLayout.posterWidth,
                            height: FeaturedCarouselLayout.posterHeight,
                            child: movie.posterUrl.isEmpty
                                ? Container(
                                    color: const Color(0xFF292929),
                                    child: const Icon(
                                      Icons.movie,
                                      color: gold,
                                      size: 18,
                                    ),
                                  )
                                : FlixoraCachedImage(
                                    imageUrl: movie.posterUrl,
                                    isOnline: _online,
                                    fit: BoxFit.cover,
                                    memCacheWidth:
                                        (FeaturedCarouselLayout.posterWidth * 3).round(),
                                    memCacheHeight:
                                        (FeaturedCarouselLayout.posterHeight * 3).round(),
                                    placeholder: Container(
                                      color: const Color(0xFF292929),
                                    ),
                                    fallback: Container(
                                      color: const Color(0xFF292929),
                                      child: const Icon(
                                        Icons.movie,
                                        color: gold,
                                        size: 18,
                                      ),
                                    ),
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
      ),
    );
  }

  String _homeCategory = 'Trending';
  final Map<String, String> _sectionFilters = {};

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
          ...flixoraMovies.where((title) => title.mediaType == 'tv'),
        ]);
      case 'Anime':
        return _deduplicateMovies([
          ...anime,
          ...flixoraMovies.where((title) => title.mediaType == 'tv' &&
              _isAnimeTitle(title)),
        ]);
      case 'Korean Drama':
        return _deduplicateMovies([
          ...koreanDrama,
          ...flixoraMovies.where((title) =>
              title.mediaType == 'tv' &&
              title.originalLanguage.toLowerCase() == 'ko'),
        ]);
      case 'Bengali':
        return _deduplicateMovies([
          ...bengaliMovies, ...bengaliTv,
          ...flixoraMovies.where((title) =>
              title.originalLanguage.toLowerCase() == 'bn' ||
              title.originCountry.toUpperCase().contains('BD')),
        ]);
      case 'Flixora Originals':
        return flixoraMovies;
      default:
        return [];
    }
  }

  Widget _homeTopCategories() {
    const categories = [
      'Trending', 'Movies', 'TV Series', 'Anime',
      'Korean Drama', 'Bengali', 'Flixora Originals',
    ];
    final available = categories.where(
      (category) => _moviesForHomeCategory(category).isNotEmpty,
    ).toList();
    if (available.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: available.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final category = available[index];
          final selected = category == _homeCategory;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _homeCategory = category),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: selected ? white : ink60,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
                child: Text(category),
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
          _homeTopCategories(),
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
                TextButton(onPressed: () => setState(() => _homeCategory = 'Trending'), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact), child: const Text('Show all', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
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
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          _homeTopCategories(),
          _featuredSlider(),
          _ottHomeSection(),
          if (flixoraMovies.isNotEmpty) _sectionBlock('Flixora Originals', flixoraMovies),
          _sectionBlock('Trending Movies', _homeTrendingMovies()),
          _sectionBlock('Trending TV Series', _deduplicateMovies([
            ...trendingTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ])),
          _sectionBlock('Drama', _deduplicateMovies([
            ...trendingTv, ...popularTv, ...topRatedTv,
            ...bengaliTv, ...koreanDrama, ...indianDramaTv, ...flixoraMovies,
          ]).where((title) => title.mediaType == 'tv' && title.genres.any(
            (genre) => genre.toLowerCase().contains('drama'),
          )).toList()),
          _sectionBlock('Web Series', _webSeriesTitles()),
          _sectionBlock('Anime', _deduplicateMovies([
            ...anime,
            ...flixoraMovies.where((title) => title.mediaType == 'tv' &&
                title.genres.any((genre) => genre.toLowerCase() == 'anime')),
          ])),
          _sectionBlock('Korean & Asian Drama', koreanDrama),
          _sectionBlock('Bengali Movies', bengaliMovies),
          _sectionBlock('Bengali TV Series', bengaliTv),
          _sectionBlock('Popular Movies', _withoutFlixoraDuplicates(popular)),
          _sectionBlock('Popular TV Series', _deduplicateMovies([
            ...popularTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ])),
          _sectionBlock('Now Playing', _withoutFlixoraDuplicates(latest)),
          _sectionBlock('Top Rated Movies', _withoutFlixoraDuplicates(topRated)),
          _sectionBlock('Top Rated TV Series', _deduplicateMovies([
            ...topRatedTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ])),
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
          style: const TextStyle(color: ink54),
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.60,
        crossAxisSpacing: 9,
        mainAxisSpacing: 12,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF17181C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF292B31), width: 0.8),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _isOpeningTitle ? null : () => _playMovie(movie),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          movie.posterUrl.isEmpty
                              ? Container(
                                  color: panel,
                                  child: const Icon(Icons.movie, color: gold),
                                )
                              : FlixoraCachedImage(
                                  imageUrl: movie.posterUrl,
                                  isOnline: _online,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 300,
                                  memCacheHeight: 450,
                                  fallback: Container(
                                    color: panel,
                                    child: const Icon(Icons.movie, color: gold),
                                  ),
                                ),
                          if (_hasHindiAudio(movie))
                            Positioned(
                              top: 5,
                              right: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xDD111216),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Hindi',
                                  style: TextStyle(
                                    color: white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: 38,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: const BoxDecoration(
                      color: Color(0xFF202126),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(7),
                      ),
                    ),
                    child: Text(
                      _displayTitle(movie),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchFilterBar(List<Movie> source) {
    final filters = _availableSearchFilters(source);
    final selected = filters.contains(_searchCategory)
        ? _searchCategory
        : 'All';
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final active = filter == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _searchCategory = filter),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(top: 2, bottom: 5),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? gold : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: active ? white : ink60,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _searchForTitle(String title) {
    _searchController.text = title;
    _searchController.selection = TextSelection.collapsed(
      offset: title.length,
    );
    _onSearchChanged(title);
    if (!_searchOpen) _openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  Widget _searchResultRow(Movie movie, {int? rank}) {
    final metadata = <String>[
      if (movie.rating > 0) movie.rating.toStringAsFixed(1),
      if (movie.year.isNotEmpty && movie.year != 'N/A') movie.year,
      if (movie.originCountry.isNotEmpty) movie.originCountry,
      if (movie.genres.isNotEmpty) movie.genres.first,
    ].join(' | ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: const Color(0xFF15161A),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _isOpeningTitle ? null : () => _playMovie(movie),
          child: SizedBox(
            height: 94,
            child: Row(
              children: [
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 62,
                    height: 82,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        movie.posterUrl.isEmpty
                            ? Container(
                                color: panel,
                                child: const Icon(Icons.movie, color: gold),
                              )
                            : FlixoraCachedImage(
                                imageUrl: movie.posterUrl,
                                isOnline: _online,
                                fit: BoxFit.cover,
                                memCacheWidth: 186,
                                memCacheHeight: 246,
                                fallback: Container(
                                  color: panel,
                                  child: const Icon(Icons.movie, color: gold),
                                ),
                              ),
                        if (rank != null)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: const BoxDecoration(
                                color: gold,
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(6),
                                ),
                              ),
                              child: Text(
                                '$rank',
                                style: const TextStyle(
                                  color: Color(0xFF171717),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        if (_hasHindiAudio(movie))
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: const Color(0xCC111216),
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: const Text(
                                'Hindi',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _displayTitle(movie),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(
                              movie.mediaType == 'tv'
                                  ? Icons.live_tv_rounded
                                  : Icons.movie_creation_outlined,
                              color: ink60,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            if (movie.rating > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                color: premiumGold,
                                size: 14,
                              ),
                              const SizedBox(width: 2),
                            ],
                            Expanded(
                              child: Text(
                                metadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ink60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Play ${movie.title}',
                  onPressed: _isOpeningTitle ? null : () => _playMovie(movie),
                  icon: const CircleAvatar(
                    radius: 15,
                    backgroundColor: gold,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFF151515),
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchLandingContent() {
    final discovery = _searchDiscoveryMovies();
    final suggestions = _searchSuggestions();
    final filters = _availableSearchFilters(discovery);
    final selected = filters.contains(_searchCategory)
        ? _searchCategory
        : 'All';
    final visible = _filterSearchMovies(discovery, selected)
        .take(16)
        .toList();

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 16, 10),
          child: Text(
            '🔥 Everyone is searching',
            style: TextStyle(
              color: white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((movie) {
              return ActionChip(
                backgroundColor: const Color(0xFF25262B),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    _displayTitle(movie),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                onPressed: () => _searchForTitle(movie.title),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _searchFilterBar(discovery),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Trending now',
            style: TextStyle(
              color: white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No titles available yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ink60),
            ),
          )
        else
          ...List.generate(
            visible.length,
            (index) => _searchResultRow(visible[index], rank: index + 1),
          ),
      ],
    );
  }

  Widget _searchContent() {
    final filters = _availableSearchFilters(searchResults);
    return Column(
      children: [
        _searchFilterBar(searchResults),
        Expanded(
          child: _searchLoading
              ? const Center(
                  child: CircularProgressIndicator(color: gold),
                )
              : searchResults.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchError ?? 'No results found.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: ink60),
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(top: 4, bottom: 18),
                      itemCount: _filterSearchMovies(
                        searchResults,
                        filters.contains(_searchCategory)
                            ? _searchCategory
                            : 'All',
                      ).length,
                      itemBuilder: (context, index) {
                        final filtered = _filterSearchMovies(
                          searchResults,
                          filters.contains(_searchCategory)
                              ? _searchCategory
                              : 'All',
                        );
                        return _searchResultRow(filtered[index]);
                      },
                    ),
        ),
      ],
    );
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


  Future<void> _loadOttProviders() async {
    if (apiKey.isEmpty || !_online) return;
    if (mounted) {
      setState(() {
        _ottProvidersLoading = true;
        _ottProvidersError = null;
      });
    }
    try {
      final providers = await OttCatalogService.getProviders(apiKey: apiKey);
      if (!mounted) return;
      final selectedId = _selectedOttProvider?.id;
      setState(() {
        _ottProviders = providers;
        _ottProvidersLoading = false;
        if (selectedId != null) {
          _selectedOttProvider = providers.cast<OttProvider?>().firstWhere(
            (provider) => provider?.id == selectedId,
            orElse: () => null,
          );
        }
      });
      if (_selectedOttProvider != null) {
        await _loadOttProviderTitles(_selectedOttProvider!);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ottProvidersLoading = false;
        _ottProvidersError = 'Could not load streaming platforms. Please retry.';
      });
      debugPrint('OTT provider catalogue error: $error');
    }
  }

  Future<void> _loadOttProviderTitles(OttProvider provider) async {
    if (!_online || apiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _ottTitlesError = 'Connect to the internet to browse this platform.';
          _ottProviderTitles = [];
        });
      }
      return;
    }
    final requestedRegion = _ottRegion;
    final requestedFilter = _ottMediaFilter;
    setState(() {
      _selectedOttProvider = provider;
      _ottTitlesLoading = true;
      _ottTitlesError = null;
      _ottProviderTitles = [];
    });
    try {
      final rows = await OttCatalogService.getProviderTitles(
        apiKey: apiKey,
        providerId: provider.id,
        region: requestedRegion,
        mediaFilter: requestedFilter == 'Movies' || requestedFilter == 'TV Series'
            ? requestedFilter
            : 'All',
      );
      final titles = rows.map((row) {
        final mediaType = (row['media_type'] ?? 'movie').toString();
        final catalogueMovie = Movie.fromJson(row, mediaType: mediaType);
        for (final adminTitle in flixoraMovies) {
          if (adminTitle.tmdbId > 0 &&
              adminTitle.tmdbId == catalogueMovie.tmdbId &&
              adminTitle.mediaType == mediaType) {
            return adminTitle.withFallbackMetadata(catalogueMovie);
          }
        }
        return catalogueMovie;
      }).toList();
      if (!mounted ||
          _selectedOttProvider?.id != provider.id ||
          _ottRegion != requestedRegion ||
          _ottMediaFilter != requestedFilter) return;
      setState(() {
        _ottProviderTitles = _deduplicateMovies(titles);
        _ottTitlesLoading = false;
      });
    } catch (error) {
      if (!mounted ||
          _selectedOttProvider?.id != provider.id ||
          _ottRegion != requestedRegion ||
          _ottMediaFilter != requestedFilter) return;
      setState(() {
        _ottTitlesLoading = false;
        _ottTitlesError = 'Could not load titles for ${provider.name}.';
      });
      debugPrint('OTT title discovery error: $error');
    }
  }

  void _changeOttRegion(String? region) {
    if (region == null || region == _ottRegion) return;
    setState(() => _ottRegion = region);
    final provider = _selectedOttProvider;
    if (provider != null) unawaited(_loadOttProviderTitles(provider));
  }

  void _changeOttMediaFilter(String filter) {
    if (_ottMediaFilter == filter) return;
    setState(() => _ottMediaFilter = filter);
    final provider = _selectedOttProvider;
    if (provider != null) unawaited(_loadOttProviderTitles(provider));
  }

  void _openOttProvider(OttProvider provider) {
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = 1;
      _search = '';
      _searchController.clear();
      _showRanking = false;
      _ottMediaFilter = 'All';
      _selectedOttProvider = provider;
    });
    unawaited(_loadOttProviderTitles(provider));
  }

  Widget _ottProviderLogo(OttProvider provider, {double size = 58}) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: ink12),
      ),
      child: provider.logoUrl.isEmpty
          ? const Icon(Icons.live_tv_rounded, color: gold, size: 25)
          : ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(
                provider.logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.live_tv_rounded,
                  color: gold,
                  size: 25,
                ),
              ),
            ),
    );
  }

  Widget _ottHomeSection() {
    if (_ottProviders.isEmpty && !_ottProvidersLoading) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Stream on OTT',
                  style: TextStyle(
                    color: white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _tab = 1;
                  _search = '';
                  _searchController.clear();
                }),
                child: const Text(
                  'Explore all',
                  style: TextStyle(color: gold, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        if (_ottProvidersLoading && _ottProviders.isEmpty)
          const SizedBox(
            height: 78,
            child: Center(
              child: CircularProgressIndicator(color: gold, strokeWidth: 2),
            ),
          )
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: _ottProviders.take(18).length,
              separatorBuilder: (_, __) => const SizedBox(width: 13),
              itemBuilder: (context, index) {
                final provider = _ottProviders[index];
                return GestureDetector(
                  onTap: () => _openOttProvider(provider),
                  child: SizedBox(
                    width: 68,
                    child: Column(
                      children: [
                        _ottProviderLogo(provider, size: 60),
                        const SizedBox(height: 5),
                        Text(
                          provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ink70,
                            fontSize: 10,
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
    );
  }

  List<Movie> _filteredOttProviderTitles() {
    final titles = _ottProviderTitles;
    switch (_ottMediaFilter) {
      case 'Movies':
        return titles.where((movie) => movie.mediaType == 'movie').toList();
      case 'TV Series':
        return titles.where((movie) => movie.mediaType == 'tv').toList();
      case 'Anime':
        return titles.where((title) {
          final genres = title.genres.map((genre) => genre.toLowerCase()).toSet();
          return genres.contains('anime') ||
              (genres.contains('animation') &&
                  (title.originalLanguage.toLowerCase() == 'ja' ||
                      title.originCountry.toUpperCase() == 'JP'));
        }).toList();
      case 'Drama':
        return titles.where((movie) => movie.genres.any(
          (genre) => genre.toLowerCase() == 'drama',
        )).toList();
      case 'Documentary':
        return titles.where((movie) => movie.genres.any(
          (genre) => genre.toLowerCase() == 'documentary',
        )).toList();
      default:
        return titles;
    }
  }

  Widget _ottContent() {
    const mediaFilters = [
      'All', 'Movies', 'TV Series', 'Anime', 'Drama', 'Documentary',
    ];
    final selectedProvider = _selectedOttProvider;
    final titles = _filteredOttProviderTitles();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Explore streaming platforms',
                  style: TextStyle(color: ink60, fontSize: 13),
                ),
              ),
              const Text('Region', style: TextStyle(color: ink54, fontSize: 11)),
              const SizedBox(width: 7),
              DropdownButton<String>(
                value: _ottRegion,
                dropdownColor: panel,
                underline: const SizedBox.shrink(),
                style: const TextStyle(
                  color: white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                items: const [
                  DropdownMenuItem(value: 'BD', child: Text('🇧🇩 BD')),
                  DropdownMenuItem(value: 'IN', child: Text('🇮🇳 IN')),
                  DropdownMenuItem(value: 'US', child: Text('🇺🇸 US')),
                  DropdownMenuItem(value: 'GB', child: Text('🇬🇧 UK')),
                  DropdownMenuItem(value: 'CA', child: Text('🇨🇦 CA')),
                  DropdownMenuItem(value: 'AU', child: Text('🇦🇺 AU')),
                ],
                onChanged: _changeOttRegion,
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Platform logos show catalogue availability for the selected region. Playback and audio tracks depend on the video source available in FLIXORA.',
            style: TextStyle(color: ink54, fontSize: 10, height: 1.35),
          ),
        ),
        SizedBox(
          height: 106,
          child: _ottProvidersLoading && _ottProviders.isEmpty
              ? const Center(child: CircularProgressIndicator(color: gold))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  itemCount: _ottProviders.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 13),
                  itemBuilder: (context, index) {
                    final provider = _ottProviders[index];
                    final selected = selectedProvider?.id == provider.id;
                    return GestureDetector(
                      onTap: () => _loadOttProviderTitles(provider),
                      child: SizedBox(
                        width: 70,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(19),
                                border: Border.all(
                                  color: selected ? gold : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: _ottProviderLogo(provider, size: 58),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              provider.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: selected ? gold : ink70,
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_ottProvidersError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Text(
              _ottProvidersError!,
              style: const TextStyle(color: ink60, fontSize: 12),
            ),
          ),
        if (selectedProvider == null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app_rounded, color: gold, size: 36),
                  const SizedBox(height: 10),
                  const Text(
                    'Choose a platform to explore its catalogue',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ink70, fontSize: 13),
                  ),
                  if (_ottProvidersError != null)
                    TextButton(
                      onPressed: _loadOttProviders,
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedProvider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _ottRegion,
                  style: const TextStyle(color: gold, fontSize: 11),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: mediaFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final filter = mediaFilters[index];
                final selected = _ottMediaFilter == filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: selected,
                  onSelected: (_) => _changeOttMediaFilter(filter),
                  selectedColor: gold,
                  backgroundColor: panel,
                  side: BorderSide(color: selected ? gold : ink24),
                  labelStyle: TextStyle(
                    color: selected ? white : ink70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _ottTitlesLoading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : _ottTitlesError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _ottTitlesError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: ink60),
                            ),
                            TextButton(
                              onPressed: () => _loadOttProviderTitles(selectedProvider),
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    : titles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: Text(
                                'No ${_ottMediaFilter.toLowerCase()} titles found for ${selectedProvider.name} in $_ottRegion. Try another region or category.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: ink54, height: 1.4),
                              ),
                            ),
                          )
                        : _collectionContent(
                            selectedProvider.name + ' · ' + _ottMediaFilter,
                            titles,
                          ),
          ),
        ],
      ],
    );
  }

  Widget _libraryContent() {
    const sections = ['Downloads', 'My List', 'Favourites', 'History'];
    Widget content;
    switch (_librarySection) {
      case 'My List':
        content = _collectionContent('My List', _moviesForIds(_saved));
        break;
      case 'Favourites':
        content = _collectionContent('Favourites', _moviesForIds(_favourites));
        break;
      case 'History':
        content = _watchHistoryPage();
        break;
      case 'Downloads':
      default:
        content = _downloadsContent();
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Text(
            'Everything you keep, in one place.',
            style: TextStyle(color: ink60, fontSize: 13),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            scrollDirection: Axis.horizontal,
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final section = sections[index];
              final selected = section == _librarySection;
              return ChoiceChip(
                label: Text(section),
                selected: selected,
                onSelected: (_) => setState(() => _librarySection = section),
                selectedColor: gold,
                backgroundColor: panel,
                side: BorderSide(color: selected ? gold : ink24),
                labelStyle: TextStyle(
                  color: selected ? white : ink70,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              );
            },
          ),
        ),
        Expanded(child: content),
      ],
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
                    style: const TextStyle(color: ink54, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: user == null ? _showVisitorLogin : _signOutVisitor,
              child: Text(user == null ? 'Login / Sign Up' : 'Logout'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              _cineProfileStat('WATCHED', _watchHistory.length.toString()),
              _cineProfileDivider(),
              _cineProfileStat('MY LIST', _saved.length.toString()),
              _cineProfileDivider(),
              _cineProfileStat(
                'DOWNLOADS',
                _downloads.where((task) => task.status == 'Completed').length.toString(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
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
              trailing: const Icon(Icons.chevron_right, color: ink54)),
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
            style: TextStyle(color: ink38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _cineProfileStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: gold,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: ink54,
              fontSize: 9,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cineProfileDivider() {
    return Container(width: 1, height: 34, color: ink12);
  }

  Widget _watchHistoryPreview() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 2, 10),
        child: Row(children: [
          const Icon(Icons.history, color: ink70, size: 20),
          const SizedBox(width: 9),
          const Expanded(child: Text('Watch History', style: TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))),
          Text('${_watchHistory.length}', style: const TextStyle(color: ink54)),
          IconButton(tooltip: 'View all watch history', onPressed: () => _openProfileSection('Watch History'), icon: const Icon(Icons.chevron_right, color: ink70, size: 25)),
        ]),
      ),
      if (_watchHistory.isEmpty)
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text('Movies you play will appear here.', style: TextStyle(color: ink54)))
      else
        SizedBox(height: 112, child: ListView.separated(
          scrollDirection: Axis.horizontal, itemCount: _watchHistory.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final movie = _watchHistory[index];
            final image = movie.backdropUrl.isNotEmpty ? movie.backdropUrl : movie.posterUrl;
            return GestureDetector(onTap: _isOpeningTitle ? null : () => _playMovie(movie), child: SizedBox(width: 148, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            const Text('Recently watched', style: TextStyle(color: ink60, fontSize: 12, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
          ])),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: ink60), color: panel,
            onSelected: (value) async {
              if (value == 'remove') {
                setState(() => _watchHistory.removeWhere((item) => item.id == movie.id));
                await MovieCache.saveList(MovieCache.historyKey, _watchHistory);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove from history'))],
          ),
          IconButton(tooltip: 'Play', onPressed: _isOpeningTitle ? null : () => _playMovie(movie), icon: const CircleAvatar(radius: 17, backgroundColor: ink70, child: Icon(Icons.play_arrow, color: Colors.white, size: 21))),
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
      leading: Icon(icon, color: ink70),
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
                  style: const TextStyle(color: ink54)),
            ),
          const Icon(Icons.chevron_right, color: ink54),
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
      value: value, onChanged: onChanged, activeThumbColor: ink,
      activeTrackColor: gold, inactiveThumbColor: ink,
      inactiveTrackColor: ink24,
      title: Text(title, style: const TextStyle(color: white, fontSize: 15, fontStyle: FontStyle.italic)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 7), child: Text(subtitle, style: const TextStyle(color: ink60, fontSize: 12, height: 1.3))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  Widget _settingsContent() {
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 16), children: [
        const Padding(padding: EdgeInsets.fromLTRB(4, 2, 4, 9), child: Text('Your app and preferences', style: TextStyle(color: ink70, fontSize: 13))),
        _profileGroup([
          _profileTile(Icons.notifications_none, 'Notifications', () => _saveBoolSetting('flixora_notifications', !_notificationsEnabled, (x) => _notificationsEnabled = x),
            trailing: Switch(value: _notificationsEnabled, onChanged: (v) => _saveBoolSetting('flixora_notifications', v, (x) => _notificationsEnabled = x), activeThumbColor: ink, activeTrackColor: gold)),
          _profileTile(Icons.language, 'Language', _showLanguagePicker, trailingText: _appLanguage),
          _profileTile(Icons.tune, 'Watch Options', _showWatchOptions, trailingText: _preferredQuality),
          _settingSwitch(title: 'Family Mode', subtitle: 'Helps keep the catalogue suitable for family viewing.', value: _familyMode, onChanged: (v) => _saveBoolSetting('flixora_family_mode', v, (x) => _familyMode = x)),
          _settingSwitch(title: 'Download in background', subtitle: 'Keep download tasks active while you use other screens.', value: _downloadInBackground, onChanged: (v) => _saveBoolSetting('flixora_download_background', v, (x) => _downloadInBackground = x)),
          _settingSwitch(title: 'Auto activate Miniplayer', subtitle: 'Miniplayer behavior will be connected when the player feature is extended.', value: _autoMiniPlayer, onChanged: (v) => _saveBoolSetting('flixora_auto_miniplayer', v, (x) => _autoMiniPlayer = x)),
          _profileTile(Icons.privacy_tip_outlined, 'Privacy Settings', () => _showSettingsInfo('Privacy Settings', 'Your watch history, saved list and app preferences are currently stored on this device. Account sync and privacy controls will be expanded with the visitor account backend.')),
        ]),
        const SizedBox(height: 20),
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 9), child: Text('More info and support', style: TextStyle(color: ink70, fontSize: 13))),
        _profileGroup([
          _profileTile(Icons.system_update, 'Check update', () => _showSettingsInfo('Check update', 'Automatic update checking is not connected to a release service yet. Install new FLIXORA versions from the official release when available.')),
          _profileTile(Icons.info_outline, 'About us', () => _showSettingsInfo('About FLIXORA', 'FLIXORA is a free movie and series discovery and streaming app.')),
          _profileTile(Icons.policy_outlined, 'Privacy Policy', () => _showSettingsInfo('Privacy Policy', 'The public privacy policy page will be added before release.')),
          _profileTile(Icons.description_outlined, 'User Agreement', () => _showSettingsInfo('User Agreement', 'The user agreement page will be added before release.')),
        ]),
      ])),
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
                style: const TextStyle(color: ink54, height: 1.4)),
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
                obscureText: true,                style: const TextStyle(color: white),
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
                      email: email,
                      password: password,
                      emailRedirectTo: authRedirectUrl,
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
            counterStyle: TextStyle(color: ink54),
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

  List<Movie> _rankingMovies() {
    if (_rankingTv) {
      switch (_rankingCategory) {
        case 'Top Series': {
          final series = _deduplicateMovies([
            ...topRatedTv, ...popularTv, ...trendingTv, ...anime,
            ...koreanDrama, ...bengaliTv, ...indianDramaTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ]);
          return series..sort((a, b) => b.rating.compareTo(a.rating));
        }
        case 'New Bengali':
          return _deduplicateMovies(bengaliTv);
        case 'Anime':
          return _deduplicateMovies([
            ...anime,
            ...flixoraMovies.where((title) => title.mediaType == 'tv' &&
                title.genres.any((genre) => genre.toLowerCase() == 'anime')),
          ]);
        case 'Drama': {
          return _deduplicateMovies([
            ...topRatedTv, ...popularTv, ...trendingTv,
            ...bengaliTv, ...koreanDrama, ...indianDramaTv, ...flixoraMovies,
          ]).where((title) => title.mediaType == 'tv' && title.genres.any(
            (genre) => genre.toLowerCase().contains('drama'),
          )).toList();
        }
        case 'Web Series':
          return _webSeriesTitles();
        case 'Asian Drama':
          return _deduplicateMovies(koreanDrama);
        case 'Indian Drama':
          return _deduplicateMovies(indianDramaTv);
        default:
          return _deduplicateMovies([
            ...trendingTv, ...popularTv, ...topRatedTv, ...anime,
            ...koreanDrama, ...bengaliTv, ...indianDramaTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ]);
      }
    }
    switch (_rankingCategory) {
      case 'TOP Movies':
        final movies = _deduplicateMovies([
          ...topRated, ...popular, ...trending,
        ].where((movie) => movie.mediaType == 'movie').toList());
        return movies..sort((a, b) => b.rating.compareTo(a.rating));
      case 'New Bengali':
        return _deduplicateMovies(bengaliMovies);
      case 'Bollywood':
        return _deduplicateMovies(bollywoodMovies);
      case 'Hollywood':
        return _deduplicateMovies(hollywoodMovies);
      case 'South Indian':
        return _deduplicateMovies(southIndianMovies);
      case 'New Release':
        return _deduplicateMovies(_withoutFlixoraDuplicates(latest));
      default:
        return _deduplicateMovies([
          ...flixoraMovies, ...trending, ...popular, ...latest, ...topRated,
        ].where((movie) => movie.mediaType == 'movie').toList());
    }
  }

  Widget _rankingContent() {
    const movieCategories = [
      'Cinema', 'TOP Movies', 'New Bengali', 'Bollywood',
      'Hollywood', 'South Indian', 'New Release',
    ];
    const tvCategories = [
      'All Series', 'Top Series', 'New Bengali',
      'Anime', 'Drama', 'Web Series', 'Asian Drama', 'Indian Drama',
    ];
    final categories = _rankingTv ? tvCategories : movieCategories;
    final movies = _rankingMovies();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 126, child: ColoredBox(color: const Color(0xFF11141C), child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20), itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index]; final selected = category == _rankingCategory;
          return InkWell(
            onTap: () => setState(() => _rankingCategory = category),
            child: Container(
              height: 58,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? gold.withValues(alpha: 0.16) : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: selected ? gold : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              child: Text(
                category,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? gold : const Color(0xFFD4DAE4),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ))),
      Expanded(child: movies.isEmpty ? const Center(child: Text('No movies available in this category.', style: TextStyle(color: ink54))) : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          return Padding(padding: const EdgeInsets.only(bottom: 18), child: SizedBox(height: 112, child: Row(children: [
            GestureDetector(
              onTap: _isOpeningTitle ? null : () => _playMovie(movie),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 76,
                  height: 108,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      movie.posterUrl.isEmpty
                          ? Container(color: panel, child: const Icon(Icons.movie, color: gold))
                          : FlixoraCachedImage(
                              imageUrl: movie.posterUrl,
                              isOnline: _online,
                              fit: BoxFit.cover,
                              memCacheWidth: 228,
                              memCacheHeight: 324,
                              fallback: Container(color: panel, child: const Icon(Icons.movie, color: gold)),
                            ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: index == 0 ? const Color(0xFFE83E9B) : const Color(0xFF2787E8),
                            borderRadius: const BorderRadius.only(bottomRight: Radius.circular(7)),
                          ),
                          child: Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: const TextStyle(color: white, fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(movie.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              Row(children: [const Icon(Icons.star, color: premiumGold, size: 16), const SizedBox(width: 4), Text(movie.rating.toStringAsFixed(1), style: const TextStyle(color: premiumGold, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Flexible(child: Text(movie.year, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ink54, fontSize: 11)))]),
            ])),
            IconButton(onPressed: _isOpeningTitle ? null : () => _playMovie(movie), icon: const Icon(Icons.play_circle_fill, color: gold, size: 34), tooltip: 'Play'),
          ])));
        },
      )),
    ]);
  }

  Widget _currentPage() {
    if (_showRanking) return _rankingContent();
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
              style: TextStyle(color: ink54),
            ),
          );
        }

        return _homeContent();

      case 1:
        return _ottContent();
      case 2:
        return _libraryContent();
      case 3:
        return _profileSection == null
            ? _profileContent()
            : _profileSectionContent();
      default:
        return _homeContent();
    }
  }

  Widget _bottomNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _search = '';
            _showRanking = false;
            _searchController.clear();
            _searchLoading = false;
            _profileSection = null;
            _tab = index;
          });
        },
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, size: 22, color: selected ? gold : ink60),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: selected ? gold : ink60, fontSize: 11, height: 1.0, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ],          ),
        ),
      ),
    );
  }

  String _pageTitle() {
    if (_search.isNotEmpty) return 'Search Results';

    if (_tab == 1) return 'OTT';
    if (_tab == 2) return 'Library';
    if (_tab == 3) return _profileSection ?? 'CineProfile';
    return 'FLIXORA';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: _tab == 0 && _search.isEmpty && !_showRanking,
      appBar: AppBar(
        backgroundColor: _tab == 0 && _search.isEmpty && !_showRanking ? Colors.transparent : bg,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        centerTitle: _showRanking,
        toolbarHeight: _showRanking ? kToolbarHeight : (_tab == 0 ? 62 : kToolbarHeight),
        titleSpacing: _tab == 0 && !_showRanking ? 8 : 16,
        leading: _showRanking ? IconButton(onPressed: () => setState(() => _showRanking = false), icon: const Icon(Icons.arrow_back)) : (_tab == 3 && _profileSection != null ? IconButton(onPressed: () => setState(() => _profileSection = null), icon: const Icon(Icons.arrow_back)) : null),
        title: _showRanking ? const Text('Ranking', style: TextStyle(color: white, fontWeight: FontWeight.w700)) : _tab == 0
            ? Row(
                children: [
                  Image.asset(
                    'assets/images/flixora_logo.png',
                    width: 39,
                    height: 39,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: white.withValues(alpha: 0.24)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onSubmitted: _onSearchChanged,
                        style: const TextStyle(color: white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search movies & series...',
                          hintStyle: const TextStyle(
                            color: ink54,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: ink70,
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
                                    color: ink54,
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
                      foregroundColor: gold,
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
                ),
              ),
        actions: _tab == 0 || _showRanking
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
                      color: _online ? gold : Colors.redAccent,
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
      bottomNavigationBar: _showRanking ? null : Container(
        color: panel,
        child: SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Container(
            height: 56,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ink10, width: 0.5)),
            ),
            child: Row(
              children: [
                _bottomNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
                _bottomNavItem(1, Icons.live_tv_outlined, Icons.live_tv, 'OTT'),
                _bottomNavItem(2, Icons.video_library_outlined, Icons.video_library, 'Library'),
                _bottomNavItem(3, Icons.person_outline, Icons.person, 'Profile'),
              ],
            ),
          ),
        ),
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
                'Connect to the internet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'When your internet connection is restored: Explore various movies, TV series and more',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 25),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.white,
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
              const Icon(Icons.download_outlined, size: 65, color: goldLight),
              const SizedBox(height: 15),
              const Text(
                'No Downloads Yet',
                style: TextStyle(
                  color: white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your saved videos will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            'Saved Videos',
            style: TextStyle(
              color: white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              final completed = task.status == 'Completed';
              final failed = task.status == 'Failed';
              final statusColor = completed
                  ? const Color(0xFF39E69B)
                  : failed
                      ? Colors.redAccent
                      : goldLight;
              final percent = (task.progress * 100).round().clamp(0, 100);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: completed
                        ? const Color(0x5539E69B)
                        : ink12,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: 68,
                        height: 94,
                        child: task.poster.isEmpty
                            ? Container(
                                color: bg,
                                child: const Icon(
                                  Icons.movie,
                                  color: goldLight,
                                  size: 30,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: task.poster,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: bg,
                                  child: const Icon(
                                    Icons.movie,
                                    color: goldLight,
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
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${VideoQualityService.displayName(task.quality)}  •  ${task.totalBytes > 0 ? DownloadManager.formatBytes(task.totalBytes) : 'Size unavailable'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            completed
                                ? 'Successfully Downloaded'
                                : failed
                                    ? (task.errorMessage ?? 'Download failed')
                                    : 'Downloading',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: LinearProgressIndicator(
                                    value: task.totalBytes > 0
                                        ? task.progress
                                        : (completed ? 1 : null),
                                    minHeight: 6,
                                    backgroundColor: ink24,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                completed
                                    ? '100%'
                                    : task.totalBytes > 0
                                        ? '$percent%'
                                        : DownloadManager.formatBytes(task.bytesReceived),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          if (!completed && task.bytesReceived > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Downloaded: ${DownloadManager.formatBytes(task.bytesReceived)}',
                              style: const TextStyle(
                                color: ink70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Play downloaded movie',
                          onPressed: completed && task.filePath != null
                              ? () => onPlay(task)
                              : null,
                          icon: Icon(
                            Icons.play_circle_fill,
                            color: completed ? const Color(0xFF39E69B) : ink24,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete download',
                          onPressed: completed || failed
                              ? () => onDelete(task)
                              : null,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
                        begin: Alignment.topCenter,                        end: Alignment.bottomCenter,
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
                                color: ink60,
                              ),
                            ),                            const SizedBox(height: 8),
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
                                style: const TextStyle(color: ink60),
                              ),
                            ],
                            if (movie.originalLanguage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Language: ${movie.originalLanguage.toUpperCase()}',
                                style: const TextStyle(color: ink60),
                              ),
                            ],
                            if (movie.runtime != null &&
                                movie.runtime! > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${movie.runtime} min',
                                style: const TextStyle(
                                  color: ink60,
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
                      color: ink70,
                      height: 1.6,
                      fontSize: 14,
                    ),
                  ),
                  ExternalCatalogSection(
                    title: movie.title,
                    year: movie.year,
                    mediaType: movie.mediaType,
                    tmdbId: movie.tmdbId,
                    client: supabaseClient,
                  ),
                  const SizedBox(height: 25),
                  if (movie.canAttemptPlayback)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: Colors.white,
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
                        'No supported FLIXORA playback source is linked to this title yet.',
                        style: TextStyle(color: ink60, fontSize: 13),
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
  late final Media3PlayerController _media3Controller;
  bool _usingMedia3Fallback = false;
  String? _media3FallbackUrl;
  int _media3StartPositionMs = 0;
  String? _media3Error;
  Map<String, dynamic> _media3State = <String, dynamic>{};
  int _lastMedia3UiPositionMs = -1000;
  int _lastMedia3ResumeSaveMs = 0;
  bool _media3ErrorHandling = false;
  late Future<Map<String, dynamic>> _movieDetailsFuture;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<bool>? _completedSubscription;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime? _lastPositionUiUpdate;
  int _lastResumeSaveSecond = 0;

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
  List<ProviderEmbedSource> _providerSources = [];
  ProviderEmbedSource? _selectedProviderSource;
  List<Map<String, dynamic>> _tvSeasons = [];
  List<Map<String, dynamic>> _tvEpisodes = [];
  int _selectedSeasonNumber = 1;
  int _selectedEpisodeNumber = 1;
  int? _aniListId;
  String? _tvImdbId;
  bool _loadingTvEpisodes = false;
  int _tvSeasonRequestToken = 0;
  int _publicSourceRequestToken = 0;
  String? _tvEpisodeError;
  final Set<String> _failedProviderIds = <String>{};
  bool _isSelectingDefaultProvider = false;

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
    // Dailymotion share links are provider pages, not direct media files.
    // Route them through the dedicated Player-ID embed source instead.
    if (ProviderCatalog.fromAdminUrl(legacyUrl) != null) return '';
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
    _providerSources = widget.movie.mediaType == 'tv'
        ? ProviderCatalog.forTv(
            tmdbId: widget.movie.tmdbId,
            adminVideoUrl: widget.movie.videoUrl,
          )
        : ProviderCatalog.forMovie(
            tmdbId: widget.movie.tmdbId,
            dailymotionUrl: widget.movie.videoUrl,
            adminVideoUrl: widget.movie.videoUrl,
          );
    _movieDetailsFuture = _loadPlayerMovieDetails();
    _media3Controller = Media3PlayerController(
      onState: _handleMedia3State,
      onError: _handleMedia3Error,
    );
    _player = Player();
    _videoController = VideoController(_player);

    _attachPlayerListeners();
    _loadApplicationBrightness();
    _startPlayerConnectionMonitor();
    _prepareAndInitializePlayer();
  }

  Future<Map<String, dynamic>> _loadPlayerMovieDetails() async {
    final id = widget.movie.tmdbId;
    if (id <= 0) {
      await _discoverAndMergePublicSources(
        baseSources: _providerSources,
        isTv: widget.movie.mediaType == 'tv',
        season: _selectedSeasonNumber,
        episode: _selectedEpisodeNumber,
      );
      return {};
    }
    try {
      final isTv = widget.movie.mediaType == 'tv';
      final details = await TmdbService.details(
        id,
        mediaType: isTv ? 'tv' : 'movie',
      );

      var imdbId = ProviderCatalog.imdbIdFromTmdbDetails(details);
      if (imdbId == null) {
        try {
          final externalIds = await TmdbService.externalIds(
            id,
            mediaType: isTv ? 'tv' : 'movie',
          );
          imdbId = ProviderCatalog.imdbIdFromTmdbDetails({
            'external_ids': externalIds,
          });
        } catch (error) {
          debugPrint('Could not resolve IMDb title ID: $error');
        }
      }

      if (isTv) {
        _tvImdbId = imdbId ?? '';
        final seasons = (details['seasons'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where((item) => _toInt(item['season_number']) > 0)
            .toList()
          ..sort((a, b) => _toInt(a['season_number'])
              .compareTo(_toInt(b['season_number'])));
        final firstSeason = seasons.isNotEmpty
            ? _toInt(seasons.first['season_number'])
            : 1;
        if (mounted && !_isDisposed) {
          setState(() {
            _tvSeasons = seasons;
            _selectedSeasonNumber = firstSeason;
            _selectedEpisodeNumber = 1;
          });
        }

        // Anime is catalogued as TV by TMDB. Use AniList only when TMDB's
        // metadata identifies a Japanese animated series and an exact title
        // match is found; otherwise use the season-aware TMDB TV route.
        final genres = (details['genres'] as List? ?? [])
            .whereType<Map>()
            .map((genre) => (genre['name'] ?? '').toString().toLowerCase())
            .toSet();
        final language =
            (details['original_language'] ?? '').toString().toLowerCase();
        final countries = (details['origin_country'] as List? ?? [])
            .map((country) => country.toString().toUpperCase())
            .toSet();
        final isAnime = genres.contains('animation') &&
            (language == 'ja' || countries.contains('JP'));

        int? aniListId;
        if (isAnime) {
          final firstAirDate = (details['first_air_date'] ?? '').toString();
          final year = firstAirDate.length >= 4
              ? firstAirDate.substring(0, 4)
              : widget.movie.year;
          aniListId = await AniListService.findMatchingAnimeId(
            title: (details['name'] ?? widget.movie.title).toString(),
            year: year,
          );
        }
        _aniListId = aniListId;
        await _loadTvSeasonEpisodes(firstSeason);
      } else {
        if (mounted && !_isDisposed) {
          setState(() {
            _providerSources = ProviderCatalog.forMovie(
              tmdbId: id,
              imdbId: imdbId,
              dailymotionUrl: widget.movie.videoUrl,
              adminVideoUrl: widget.movie.videoUrl,
            );
          });
          await _discoverAndMergePublicSources(
            baseSources: _providerSources,
            isTv: false,
            season: 1,
            episode: 1,
          );
        }
      }
      return details;
    } catch (e) {
      debugPrint('Could not load player title metadata: $e');
      if (mounted && !_isDisposed) {
        await _discoverAndMergePublicSources(
          baseSources: _providerSources,
          isTv: widget.movie.mediaType == 'tv',
          season: _selectedSeasonNumber,
          episode: _selectedEpisodeNumber,
        );
      }
      return {};
    }
  }

  int _aniListEpisodeNumber(int episodeNumber) {
    return EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: _tvSeasons,
          seasonNumber: _selectedSeasonNumber,
          episodeNumber: episodeNumber,
        ) ??
        episodeNumber;
  }

  Future<void> _refreshTvProviderSources({bool selectProvider = false}) async {
    final id = widget.movie.tmdbId;
    if (widget.movie.mediaType != 'tv') return;
    final season = _selectedSeasonNumber;
    final episode = _selectedEpisodeNumber;
    final sources = ProviderCatalog.forTv(
      tmdbId: id,
      imdbId: _tvImdbId,
      aniListId: _aniListId,
      seasonNumber: season,
      episodeNumber: episode,
      aniListEpisodeNumber: _aniListEpisodeNumber(episode),
      adminVideoUrl: widget.movie.videoUrl,
    );
    if (mounted && !_isDisposed) {
      setState(() {
        _providerSources = sources;
        _selectedProviderSource = null;
        _failedProviderIds.clear();
        _errorMessage = null;
      });
    }
    await _discoverAndMergePublicSources(
      baseSources: sources,
      isTv: true,
      season: season,
      episode: episode,
      selectProvider: selectProvider,
    );
  }

  List<ProviderEmbedSource> _mergePublicSources(
    List<ProviderEmbedSource> baseSources,
    List<ProviderEmbedSource> publicSources,
  ) {
    // An Admin-curated embed stays first. Verified public-domain discoveries
    // are inserted before the built-in fallback routes.
    final adminSourceId = ProviderCatalog.fromAdminUrl(
      widget.movie.videoUrl,
    )?.id;
    final ordered = <ProviderEmbedSource>[
      ...baseSources.where((source) => source.id == adminSourceId),
      ...publicSources,
      ...baseSources.where((source) => source.id != adminSourceId),
    ];
    final seenIds = <String>{};
    final seenUrls = <String>{};
    final merged = <ProviderEmbedSource>[];
    for (final source in ordered) {
      if (!seenIds.add(source.id)) continue;
      if (source.isAvailable && !seenUrls.add(source.url)) continue;
      merged.add(source);
    }
    return merged;
  }

  Future<void> _discoverAndMergePublicSources({
    required List<ProviderEmbedSource> baseSources,
    required bool isTv,
    required int season,
    required int episode,
    bool selectProvider = false,
  }) async {
    if (!_playerIsOnline) return;
    final requestToken = ++_publicSourceRequestToken;
    final peerTubeFuture = PeerTubeSourceService.discover(
      widget.movie.title,
      year: widget.movie.year,
      isTv: isTv,
      season: season,
      episode: episode,
    );
    final archiveFuture = isTv
        ? Future<List<ProviderEmbedSource>>.value(
            const <ProviderEmbedSource>[],
          )
        : PublicDomainMovieSourceService.discover(
            widget.movie.title,
            year: widget.movie.year,
            isTv: false,
          );

    var discoveryFinished = false;
    var discoveryResult = const <ProviderEmbedSource>[];
    final discoveryFuture =
        Future.wait<List<ProviderEmbedSource>>([
      peerTubeFuture,
      archiveFuture,
    ]).then((groups) {
      discoveryResult = groups.expand((items) => items).toList();
      discoveryFinished = true;
      return discoveryResult;
    });

    void applySources(List<ProviderEmbedSource> discovered) {
      if (!mounted ||
          _isDisposed ||
          requestToken != _publicSourceRequestToken) {
        return;
      }
      final merged = _mergePublicSources(baseSources, discovered);
      setState(() => _providerSources = merged);

      if (selectProvider && _selectedProviderSource == null) {
        ProviderEmbedSource? firstAvailable;
        for (final source in merged) {
          if (source.isAvailable) {
            firstAvailable = source;
            break;
          }
        }
        if (firstAvailable != null) {
          unawaited(_selectProviderSource(firstAvailable));
        }
      }
    }

    List<ProviderEmbedSource> quickSources;
    try {
      // Keep first playback responsive. If public discovery takes longer,
      // its verified results are appended in the background for later fallback.
      quickSources = await Future.any<List<ProviderEmbedSource>>([
        discoveryFuture,
        Future.delayed(
          const Duration(seconds: 2),
          () => const <ProviderEmbedSource>[],
        ),
      ]);
    } catch (error) {
      debugPrint('Public source discovery failed: $error');
      quickSources = const <ProviderEmbedSource>[];
    }

    applySources(quickSources);
    if (!discoveryFinished) {
      unawaited(discoveryFuture.then<void>((lateSources) {
        if (lateSources.isNotEmpty) applySources(lateSources);
      }).catchError((Object error) {
        debugPrint('Late public source discovery failed: $error');
      }));
    } else if (quickSources.isEmpty && discoveryResult.isNotEmpty) {
      applySources(discoveryResult);
    }
  }


  Future<void> _loadTvSeasonEpisodes(
    int seasonNumber, {
    bool selectProvider = false,
  }) async {
    if (widget.movie.tmdbId <= 0 || _isDisposed) return;
    final requestToken = ++_tvSeasonRequestToken;
    if (mounted) {
      setState(() {
        _loadingTvEpisodes = true;
        _tvEpisodeError = null;
        _selectedSeasonNumber = seasonNumber;
        _selectedEpisodeNumber = 1;
      });
    }
    List<Map<String, dynamic>> episodes = [];
    String? errorMessage;
    try {
      final season = await TmdbService.seasonDetails(
        widget.movie.tmdbId,
        seasonNumber,
      );
      episodes = (season['episodes'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
        ..sort((a, b) => _toInt(a['episode_number'])
            .compareTo(_toInt(b['episode_number'])));
    } catch (error) {
      debugPrint('Could not load TV season $seasonNumber: $error');
      errorMessage = 'Episode details are temporarily unavailable.';
    }
    final firstEpisode = episodes.isNotEmpty
        ? _toInt(episodes.first['episode_number'])
        : 1;
    if (!mounted || _isDisposed || requestToken != _tvSeasonRequestToken) return;
    setState(() {
      _tvEpisodes = episodes;
      _selectedEpisodeNumber = firstEpisode;
      _loadingTvEpisodes = false;
      _tvEpisodeError = errorMessage;
    });
    await _refreshTvProviderSources(selectProvider: selectProvider);
  }

  void _selectTvEpisode(int episodeNumber) {
    if (episodeNumber <= 0 || episodeNumber == _selectedEpisodeNumber) return;
    setState(() => _selectedEpisodeNumber = episodeNumber);
    unawaited(_refreshTvProviderSources(selectProvider: true));
  }

  Widget _tvEpisodeSelector() {
    if (widget.movie.mediaType != 'tv') return const SizedBox.shrink();

    final seasonNumbers = _tvSeasons
        .map((season) => _toInt(season['season_number']))
        .where((number) => number > 0)
        .toSet()
        .toList()
      ..sort();
    if (seasonNumbers.isEmpty) seasonNumbers.add(1);

    final episodeNumbers = _tvEpisodes
        .map((episode) => _toInt(episode['episode_number']))
        .where((number) => number > 0)
        .toSet()
        .toList()
      ..sort();

    final safeSeason = seasonNumbers.contains(_selectedSeasonNumber)
        ? _selectedSeasonNumber
        : seasonNumbers.first;
    final safeEpisode = episodeNumbers.contains(_selectedEpisodeNumber)
        ? _selectedEpisodeNumber
        : (episodeNumbers.isNotEmpty ? episodeNumbers.first : 1);
    final episodeLabel = safeEpisode.toString().padLeft(2, '0');

    final selectedEpisode = _tvEpisodes.cast<Map<String, dynamic>?>().firstWhere(
      (item) => _toInt(item?['episode_number']) == safeEpisode,
      orElse: () => null,
    );
    final selectedEpisodeName =
        (selectedEpisode?['name'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: playerPanel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.video_library_rounded,
                color: playerGoldLight,
                size: 18,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Season & Episodes',
                  style: TextStyle(
                    color: playerWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (_loadingTvEpisodes)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: playerGold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            key: ValueKey<int>(safeSeason),
            initialValue: safeSeason,
            dropdownColor: playerPanel,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Season',
              labelStyle: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 11,
              ),
              filled: true,
              fillColor: playerBg,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: playerWhite, fontSize: 13),
            items: seasonNumbers
                .map(
                  (number) => DropdownMenuItem<int>(
                    value: number,
                    child: Text('Season $number'),
                  ),
                )
                .toList(),
            onChanged: _loadingTvEpisodes
                ? null
                : (number) {
                    if (number != null &&
                        number != _selectedSeasonNumber) {
                      _loadTvSeasonEpisodes(
                        number,
                        selectProvider: true,
                      );
                    }
                  },
          ),
          const SizedBox(height: 13),
          const Text(
            'Episodes',
            style: TextStyle(
              color: playerWhite,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (episodeNumbers.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: playerGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: playerGold.withValues(alpha: 0.8),
                      ),
                    ),
                    child: const Text(
                      'All',
                      style: TextStyle(
                        color: playerGoldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  ...episodeNumbers.map((number) {
                    final selected = number == safeEpisode;
                    return Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(number.toString().padLeft(2, '0')),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: _loadingTvEpisodes
                            ? null
                            : (_) => _selectTvEpisode(number),
                        selectedColor: playerGold.withValues(alpha: 0.22),
                        backgroundColor: playerBg,
                        side: BorderSide(
                          color: selected
                              ? playerGold
                              : const Color(0x3DFFFFFF),
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? playerGoldLight
                              : playerWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  }),
                ],
              ),
            )
          else if (!_loadingTvEpisodes)
            const Text(
              'No episodes available for this season.',
              style: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 11,
              ),
            ),
          if (_tvEpisodeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _tvEpisodeError!,
              style: const TextStyle(
                color: Color(0xFFFFC56E),
                fontSize: 10,
              ),
            ),
          ],
          if (selectedEpisodeName.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              'S$safeSeason · E$episodeLabel · $selectedEpisodeName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectProviderSource(ProviderEmbedSource source) async {
    if (!source.isAvailable || !_playerIsOnline || _isDisposed) return;
    _cancelHideTimer();

    if (_usingMedia3Fallback) {
      setState(() {
        _usingMedia3Fallback = false;
        _media3FallbackUrl = null;
      });
      await _media3Controller.detach();
    }

    // Release the native decoder before mounting an embedded provider. The
    // last position is already persisted by the position listener.
    try {
      await _player.pause();
      await _player.stop();
    } catch (_) {}

    if (!mounted || _isDisposed) return;
    _failedProviderIds.clear();
    setState(() {
      _selectedProviderSource = source;
      _errorMessage = null;
      _showControls = false;
      _initialized = false;
    });

    if (source.isDirectMedia) {
      await _openDirectProviderSource(source);
    }
  }

  Future<void> _openDirectProviderSource(ProviderEmbedSource source) async {
    _isOpening = true;
    var failed = false;
    try {
      await _player.open(Media(source.url, httpHeaders: source.httpHeaders));
      if (!mounted || _isDisposed) return;
      _currentVideoUrl = source.url;
      await _restoreResumePosition();
      if (!mounted || _isDisposed) return;
      setState(() {
        _initialized = true;
        _errorMessage = null;
      });
      _startHideTimer();
    } catch (_) {
      failed = true;
      if (mounted && !_isDisposed) {
        setState(() {
          _initialized = false;
          _errorMessage = 'Could not open ' + source.name + '. Trying another stream...';
        });
      }
    } finally {
      _isOpening = false;
    }
    if (failed && mounted && !_isDisposed) {
      _tryNextProvider(source);
    }
  }

  Future<void> _selectDefaultProviderIfNeeded({bool force = false}) async {
    if (!mounted ||
        _isDisposed ||
        !_playerIsOnline ||
        widget.localFilePath != null ||
        (!force && _validVideoUrl) ||
        _selectedProviderSource != null ||
        _isSelectingDefaultProvider) {
      return;
    }

    _isSelectingDefaultProvider = true;
    try {
      // Resolve IMDb metadata before choosing Play4U. This is also important
      // when a direct Admin source fails before the metadata request completes.
      await _movieDetailsFuture;
      if (!mounted || _isDisposed || _selectedProviderSource != null) return;

      // Admin-managed direct MP4/HLS was already tried above.
      // A recognized Admin embed has priority; otherwise use the first
      // available provider in the movie/TV/anime catalog's declared order.
      final adminSource = ProviderCatalog.fromAdminUrl(widget.movie.videoUrl);
      final preferred = _providerSources.where(
        (source) => source.id == adminSource?.id && source.isAvailable,
      );
      final fallback = preferred.isNotEmpty
          ? preferred.first
          : _providerSources.cast<ProviderEmbedSource?>().firstWhere(
                (source) => source?.isAvailable == true,
                orElse: () => null,
              );

      if (fallback == null) return;

      // Stop the native engine before the WebView is mounted, releasing its
      // decoder and network request while retaining the saved resume position.
      try {
        await _saveResumePosition(_position);
        await _player.pause();
        await _player.stop();
      } catch (_) {}
      if (!mounted || _isDisposed || _selectedProviderSource != null) return;

      _failedProviderIds.clear();
      setState(() {
        _usingMedia3Fallback = false;
        _media3FallbackUrl = null;
        _selectedProviderSource = fallback;
        _showControls = false;
        _initialized = false;
        _errorMessage = null;
      });
      if (fallback.isDirectMedia) {
        await _openDirectProviderSource(fallback);
      }
    } finally {
      _isSelectingDefaultProvider = false;
    }
  }

  void _tryNextProvider(ProviderEmbedSource failedSource) {
    if (!mounted ||
        _isDisposed ||
        _selectedProviderSource?.id != failedSource.id) {
      return; // Ignore stale callbacks from a provider that is no longer active.
    }

    _failedProviderIds.add(failedSource.id);
    final selectedNextSource = ProviderCatalog.nextAvailableAfter(
      _providerSources,
      failedSource.id,
      excludedIds: _failedProviderIds,
    );

    if (selectedNextSource == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No more available provider streams. Choose another stream below.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _selectedProviderSource = selectedNextSource;
      _errorMessage = null;
      _initialized = !selectedNextSource.isDirectMedia;
    });
    if (selectedNextSource.isDirectMedia) {
      unawaited(_openDirectProviderSource(selectedNextSource));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${failedSource.name} failed to load. Trying ${selectedNextSource.name}...',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _closeProviderSource() async {
    if (!mounted || _isDisposed) return;
    setState(() {
      _usingMedia3Fallback = false;
      _media3FallbackUrl = null;
      _selectedProviderSource = null;
      _errorMessage = null;
      _showControls = true;
    });
    if (widget.localFilePath != null || _resolveInitialNetworkUrl().isNotEmpty) {
      await _initializePlayer();
    }
  }

  Widget _providerSelector() {
    // Provider adapters stay internal. FLIXORA automatically selects the
    // preferred source and falls back when playback fails, so visitors see
    // one FLIXORA player instead of a list of third-party providers.
    return const SizedBox.shrink();
  }

  String _formatPlayerReleaseDate(String value) {
    final date = DateTime.tryParse(value.trim());
    if (date == null) return value;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _playerMetadataItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: playerGoldLight, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _playerMetadata() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _movieDetailsFuture,
      builder: (context, snapshot) {
        final details = snapshot.data ?? const <String, dynamic>{};

        final rawDate = (details['release_date'] ??
                details['first_air_date'] ??
                widget.movie.releaseDate)
            .toString()
            .trim();
        final releaseDate = rawDate.isNotEmpty
            ? _formatPlayerReleaseDate(rawDate)
            : (widget.movie.year.isNotEmpty && widget.movie.year != 'N/A'
                ? widget.movie.year
                : '');

        final rawRating = details['vote_average'];
        final rating = widget.movie.rating > 0
            ? widget.movie.rating
            : (rawRating is num ? rawRating.toDouble() : 0.0);

        final countries = <String>[];
        final rawCountries = details['production_countries'];
        if (rawCountries is List) {
          for (final item in rawCountries.whereType<Map>()) {
            final country =
                (item['name'] ?? item['iso_3166_1'] ?? '').toString().trim();
            if (country.isNotEmpty && !countries.contains(country)) {
              countries.add(country);
            }
          }
        }
        if (countries.isEmpty && details['origin_country'] is List) {
          countries.addAll(
            (details['origin_country'] as List)
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty),
          );
        }
        if (countries.isEmpty && widget.movie.originCountry.isNotEmpty) {
          countries.add(widget.movie.originCountry);
        }

        final genres = <String>[];
        final rawGenres = details['genres'];
        if (rawGenres is List) {
          for (final item in rawGenres.whereType<Map>()) {
            final genre = (item['name'] ?? '').toString().trim();
            if (genre.isNotEmpty && !genres.contains(genre)) {
              genres.add(genre);
            }
          }
        }
        if (genres.isEmpty) genres.addAll(widget.movie.genres);

        final items = <Widget>[];
        final originalLanguageCode =
            (details['original_language'] ?? '').toString().trim().toLowerCase();
        const originalLanguageNames = <String, String>{
          'en': 'English', 'hi': 'Hindi', 'ur': 'Urdu', 'bn': 'Bangla',
          'ta': 'Tamil', 'te': 'Telugu', 'ml': 'Malayalam', 'kn': 'Kannada',
          'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'es': 'Spanish',
          'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'ru': 'Russian',
          'ar': 'Arabic', 'tr': 'Turkish',
        };
        final originalLanguageName =
            originalLanguageNames[originalLanguageCode] ??
            (originalLanguageCode.isEmpty ? '' : originalLanguageCode.toUpperCase());
        if (originalLanguageName.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.translate_rounded,
            'Original language: $originalLanguageName',
          ));
        }
        if (rating > 0) {
          items.add(_playerMetadataItem(
            Icons.star_rounded,
            'TMDB ${rating.toStringAsFixed(1)}/10',
          ));
        }
        if (releaseDate.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.calendar_today_rounded,
            releaseDate,
          ));
        }
        if (countries.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.public_rounded,
            countries.take(2).join(', '),
          ));
        }
        items.add(_playerMetadataItem(
          Icons.movie_filter_outlined,
          widget.movie.mediaType == 'tv' ? 'TV Series' : 'Movie',
        ));
        if (genres.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.local_offer_outlined,
            genres.take(3).join(' • '),
          ));
        }

        return Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 10),
          child: Wrap(
            spacing: 13,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: items,
          ),
        );
      },
    );
  }

  String? _media3SourceUrl() {
    if (widget.localFilePath != null) {
      final path = widget.localFilePath!.trim();
      if (path.isEmpty) return null;
      return File(path).uri.toString();
    }
    final candidate = _currentVideoUrl.trim().isNotEmpty
        ? _currentVideoUrl.trim()
        : _resolveInitialNetworkUrl().trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    return candidate;
  }

  Future<bool> _activateMedia3Fallback() async {
    if (!Platform.isAndroid ||
        !mounted ||
        _isDisposed ||
        _usingMedia3Fallback ||
        _selectedProviderSource != null) {
      return false;
    }
    final source = _media3SourceUrl();
    if (source == null || source.isEmpty) return false;
    final resumePosition = _position;

    await _saveResumePosition(resumePosition);
    try {
      await _player.pause();
      await _player.stop();
    } catch (_) {}

    if (!mounted || _isDisposed) return false;
    _position = resumePosition;
    _media3StartPositionMs = resumePosition.inMilliseconds;
    setState(() {
      _usingMedia3Fallback = true;
      _media3FallbackUrl = source;
      _media3Error = null;
      _media3State = <String, dynamic>{};
      _errorMessage = null;
      _initialized = false;
      _isPlaying = false;
      _isBuffering = true;
    });
    return true;
  }

  void _handleMedia3State(Map<String, dynamic> state) {
    if (!mounted || _isDisposed || !_usingMedia3Fallback) return;
    final positionMs = _toInt(state['positionMs']);
    final durationMs = _toInt(state['durationMs']);
    final isPlaying = state['isPlaying'] == true;
    final isBuffering = state['isBuffering'] == true;
    final isReady = state['isReady'] == true;
    final previousPlaying = _isPlaying;
    final previousBuffering = _isBuffering;
    final previousReady = _initialized;
    final oldTracks = jsonEncode([
      _media3State['audioTracks'] ?? const [],
      _media3State['textTracks'] ?? const [],
    ]);
    final newTracks = jsonEncode([
      state['audioTracks'] ?? const [],
      state['textTracks'] ?? const [],
    ]);

    _media3State = state;
    _position = Duration(milliseconds: positionMs < 0 ? 0 : positionMs);
    _duration = Duration(milliseconds: durationMs < 0 ? 0 : durationMs);
    _isPlaying = isPlaying;
    _isBuffering = isBuffering;
    _initialized = isReady;

    final shouldUpdate = (positionMs - _lastMedia3UiPositionMs).abs() >= 900 ||
        previousPlaying != isPlaying ||
        previousBuffering != isBuffering ||
        previousReady != isReady ||
        oldTracks != newTracks;
    if (shouldUpdate) {
      _lastMedia3UiPositionMs = positionMs;
      setState(() {});
    }

    if (positionMs - _lastMedia3ResumeSaveMs >= 5000) {
      _lastMedia3ResumeSaveMs = positionMs;
      unawaited(_saveResumePosition(_position));
    }
    if (state['isCompleted'] == true) {
      _clearResumePosition();
    }
  }

  void _handleMedia3Error(String message) {
    if (!mounted || _isDisposed || !_usingMedia3Fallback || _media3ErrorHandling) {
      return;
    }
    _media3ErrorHandling = true;
    _media3Error = message;
    if (widget.localFilePath != null) {
      setState(() {
        _usingMedia3Fallback = false;
        _media3FallbackUrl = null;
        _errorMessage = 'Android Media3 could not play this downloaded file: ' + message;
        _isBuffering = false;
        _initialized = false;
      });
      _media3ErrorHandling = false;
      return;
    }

    setState(() {
      _usingMedia3Fallback = false;
      _media3FallbackUrl = null;
      _errorMessage = 'Android Media3 could not play this source. Trying another provider...';
      _isBuffering = false;
      _initialized = false;
    });
    unawaited(_selectDefaultProviderIfNeeded(force: true).whenComplete(() {
      _media3ErrorHandling = false;
    }));
  }

  Future<void> _showMedia3TrackPicker(int trackType) async {
    if (!_usingMedia3Fallback) return;
    final isAudio = trackType == 1;
    final raw = _media3State[isAudio ? 'audioTracks' : 'textTracks'];
    final tracks = raw is List
        ? raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: playerPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAudio ? 'Audio tracks' : 'Subtitle tracks',
                style: const TextStyle(
                  color: playerWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: playerGoldLight),
                title: Text(isAudio ? 'Auto / Default' : 'Subtitles off',
                    style: const TextStyle(color: playerWhite)),
                onTap: () async {
                  await _media3Controller.selectTrack(
                    trackType: trackType,
                    groupIndex: -1,
                    trackIndex: -1,
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              if (tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No alternate tracks were detected.',
                      style: TextStyle(color: Color(0x99FFFFFF))),
                ),
              ...tracks.map((track) {
                final language = (track['language'] ?? '').toString().trim();
                final label = (track['label'] ?? '').toString().trim();
                final title = label.isNotEmpty
                    ? label
                    : (language.isNotEmpty ? language : 'Track');
                final selected = track['selected'] == true;
                return ListTile(
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? playerGoldLight : const Color(0x80FFFFFF),
                  ),
                  title: Text(title, style: const TextStyle(color: playerWhite)),
                  subtitle: language.isNotEmpty && language != title
                      ? Text(language, style: const TextStyle(color: Color(0x99FFFFFF)))
                      : null,
                  onTap: () async {
                    await _media3Controller.selectTrack(
                      trackType: trackType,
                      groupIndex: _toInt(track['groupIndex']),
                      trackIndex: _toInt(track['trackIndex']),
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMedia3DecoderPicker() async {
    if (!_usingMedia3Fallback) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: playerPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Android Media3 fallback',
                style: TextStyle(
                  color: playerWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Decoder mode: Automatic. Android hardware decoders are tried first; the bundled NextLib FFmpeg decoder is available when the platform decoder cannot handle the format.',
                style: TextStyle(color: Color(0xCCFFFFFF), height: 1.45),
              ),
              const SizedBox(height: 8),
              const Text(
                'This compatible NextLib release does not expose manual Hardware / Software / FFmpeg switching. That can be added after a separate Android build-toolchain upgrade.',
                style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _media3FallbackActions() {
    return Positioned(
      top: 7,
      right: 7,
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Audio tracks',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showMedia3TrackPicker(1),
              icon: const Icon(Icons.audiotrack_rounded, color: Colors.white, size: 19),
            ),
            IconButton(
              tooltip: 'Subtitles',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showMedia3TrackPicker(3),
              icon: const Icon(Icons.subtitles_rounded, color: Colors.white, size: 19),
            ),
            IconButton(
              tooltip: 'Decoder settings',
              visualDensity: VisualDensity.compact,
              onPressed: _showMedia3DecoderPicker,
              icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 19),
            ),
            IconButton(
              tooltip: 'Fullscreen',
              visualDensity: VisualDensity.compact,
              onPressed: _toggleFullscreen,
              icon: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 19),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prepareAndInitializePlayer() async {
    // Load Admin quality URLs before opening the player. This allows playback
    // even when the legacy movies.video_url field is empty.
    await _loadVideoQualities();
    if (!mounted || _isDisposed) return;

    // Admin-managed MP4/HLS always gets the first chance to play.
    await _initializePlayer();
    if (!mounted || _isDisposed || _validVideoUrl ||
        widget.localFilePath != null) {
      return;
    }

    // Resolve the real IMDb ID before choosing the default provider. This
    // avoids opening Play4U with a guessed or incomplete identifier.
    await _movieDetailsFuture;
    if (!mounted || _isDisposed) return;
    await _selectDefaultProviderIfNeeded();
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
      const Duration(seconds: 30),
      (_) => _refreshPlayerConnection(),
    );
  }

  Future<void> _refreshPlayerConnection() async {
    if (!mounted || _isDisposed) return;

    final online = await InternetService.isOnline();
    if (!mounted || _isDisposed || online == _playerIsOnline) return;

    setState(() => _playerIsOnline = online);
    if (online &&
        widget.localFilePath == null &&
        !_validVideoUrl &&
        _selectedProviderSource == null) {
      unawaited(_movieDetailsFuture.then((_) async {
        if (mounted && !_isDisposed) {
          await _selectDefaultProviderIfNeeded();
        }
      }));
    }
  }

  // Listeners are attached once. Retrying playback will not create
  // duplicate stream subscriptions.
  void _attachPlayerListeners() {
    _positionSubscription = _player.stream.position.listen((value) {
      if (!mounted || _isDisposed) return;

      final now = DateTime.now();
      if (_lastPositionUiUpdate == null ||
          now.difference(_lastPositionUiUpdate!) >=
              const Duration(milliseconds: 250) ||
          value == _duration) {
        _lastPositionUiUpdate = now;
        setState(() => _position = value);
      }

      if (_duration.inSeconds > 0 &&
          (value.inSeconds - _lastResumeSaveSecond).abs() >= 5) {
        _lastResumeSaveSecond = value.inSeconds;
        unawaited(_saveResumePosition(value));
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
      final activeProvider = _selectedProviderSource;
      if (value.trim().isNotEmpty &&
          !_isOpening &&
          activeProvider != null &&
          activeProvider.isDirectMedia &&
          _playerIsOnline) {
        _tryNextProvider(activeProvider);
        return;
      }
      if (value.trim().isNotEmpty &&
          !_isOpening &&
          _selectedProviderSource == null &&
          !_usingMedia3Fallback &&
          _playerIsOnline) {
        if (Platform.isAndroid) {
          unawaited(_activateMedia3Fallback().then((started) {
            if (!started && widget.localFilePath == null && mounted && !_isDisposed) {
              return _selectDefaultProviderIfNeeded(force: true);
            }
          }));
        } else if (widget.localFilePath == null) {
          unawaited(_selectDefaultProviderIfNeeded(force: true));
        }
      }
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
          _errorMessage = null;
          _initialized = false;
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

      final fallbackStarted = await _activateMedia3Fallback();
      if (!fallbackStarted && widget.localFilePath == null && _playerIsOnline) {
        setState(() {
          _errorMessage =
              'Unable to play this video. Trying another available stream...';
        });
        unawaited(_selectDefaultProviderIfNeeded(force: true));
      } else if (!fallbackStarted && mounted && !_isDisposed) {
        setState(() {
          _errorMessage =
              'Unable to play this downloaded file. Please try downloading it again.';
        });
      }
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
    } catch (_) {}  }

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
    if (_usingMedia3Fallback) {
      if (_isPlaying) {
        await _media3Controller.pause();
      } else {
        await _media3Controller.play();
      }
      return;
    }

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
        setState(() {          _gestureMode = 'zoom';
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
      if (_usingMedia3Fallback) {
        await _media3Controller.seekTo(previewPosition.inMilliseconds);
      } else {
        await _player.seek(previewPosition);
      }
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

    if (_usingMedia3Fallback) {
      await _media3Controller.seekTo(clamped.inMilliseconds);
    } else {
      await _player.seek(clamped);
    }

    if (mounted && !_isDisposed) {
      setState(() => _position = clamped);
    }

    _startHideTimer();
  }

  Future<void> _seekTo(double value) async {
    final target = Duration(milliseconds: value.round());

    if (_usingMedia3Fallback) {
      await _media3Controller.seekTo(target.inMilliseconds);
    } else {
      await _player.seek(target);
    }

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
    if (_usingMedia3Fallback) {
      await _media3Controller.setPlaybackSpeed(speed);
      if (mounted && !_isDisposed) setState(() => _speed = speed);
      return;
    }
    await _player.setRate(speed);

    if (!mounted || _isDisposed) return;

    setState(() => _speed = speed);
    _startHideTimer();
  }

  Future<void> _changeVolume(double value) async {
    final volume = value.clamp(0.0, 100.0);
    if (_usingMedia3Fallback) {
      await _media3Controller.setVolume(volume / 100.0);
      if (mounted && !_isDisposed) setState(() => _volume = volume);
      return;
    }

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
      if (!mounted || _isDisposed) return;
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
          backgroundColor: playerPanel,
          title: const Text(
            'External Subtitle',
            style: TextStyle(color: playerWhite),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: playerWhite),
            decoration: const InputDecoration(
              hintText: 'Enter subtitle URL',
              hintStyle: TextStyle(color: Color(0x61FFFFFF)),
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

  String _originalAudioLanguageLabel() {
    final code = widget.movie.originalLanguage
        .trim()
        .toLowerCase()
        .split('-')
        .first;
    const names = <String, String>{
      'en': 'English',
      'hi': 'Hindi',
      'bn': 'Bangla',
      'ta': 'Tamil',
      'te': 'Telugu',
      'ml': 'Malayalam',
      'kn': 'Kannada',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'ur': 'Urdu',
      'ar': 'Arabic',
    };
    return names[code] ?? (code.isEmpty ? 'Not listed' : code.toUpperCase());
  }

  void _showProviderAudioHelp() {
    final source = _selectedProviderSource;
    if (source == null) {
      _showAudioTracks();
      return;
    }
    _cancelHideTimer();
    final listedLanguages = widget.movie.audioLanguages
        .map((language) => language.trim())
        .where((language) => language.isNotEmpty)
        .toSet()
        .toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: playerPanel,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.audiotrack_rounded, color: playerGold, size: 23),
                SizedBox(width: 10),
                Text(
                  'Audio language',
                  style: TextStyle(
                    color: playerWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Original language: ${_originalAudioLanguageLabel()}',
              style: const TextStyle(color: playerWhite, fontSize: 13),
            ),
            if (listedLanguages.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                'Admin-listed languages: ${listedLanguages.join(', ')}',
                style: const TextStyle(color: playerGoldLight, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This video is playing through ${source.name}. Tap the settings or gear icon inside the video, then open Audio / Language to choose a track if the provider offers one. FLIXORA cannot add a Hindi or English dub that is not included in the stream.',
              style: const TextStyle(
                color: Color(0xFFD0D5DE),
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioTracks() {
    if (_selectedProviderSource != null) {
      _showProviderAudioHelp();
      return;
    }
    final audioTracks = _tracks.audio;
    final selectedIndex = audioTracks.isEmpty
        ? -1
        : _selectedAudioTrackIndex.clamp(0, audioTracks.length - 1).toInt();

    _cancelHideTimer();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: playerPanel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: Color(0x24FFFFFF))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x66FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: playerGold.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: playerGoldLight,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audio language',
                              style: TextStyle(
                                color: playerWhite,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Choose the audio track for this movie',
                              style: TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (audioTracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          'This stream does not expose alternate audio tracks.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(sheetContext).size.height * 0.52,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: audioTracks.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final track = audioTracks[index];
                          final selected = index == selectedIndex;
                          final label = _audioTrackLabel(track, index);
                          final rawTitle = track.title?.trim() ?? '';
                          final showTrackDetail = rawTitle.isNotEmpty &&
                              rawTitle.toLowerCase() != label.toLowerCase() &&
                              !RegExp(
                                r'^(audio|track)\s*#?\s*\d*$',
                                caseSensitive: false,
                              ).hasMatch(rawTitle);

                          return Material(
                            color: selected
                                ? playerGold.withValues(alpha: 0.13)
                                : playerBg,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _selectAudioTrack(track),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? playerGold.withValues(alpha: 0.8)
                                        : const Color(0x1FFFFFFF),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? playerGold.withValues(alpha: 0.18)
                                            : const Color(0x14FFFFFF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.audiotrack_rounded,
                                        color: selected
                                            ? playerGoldLight
                                            : const Color(0xB3FFFFFF),
                                        size: 19,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label,
                                            style: TextStyle(
                                              color: playerWhite,
                                              fontSize: 14,
                                              fontWeight: selected
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                          if (showTrackDetail) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              rawTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0x80FFFFFF),
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: playerGoldLight,
                                        size: 22,
                                      )
                                    else
                                      const Icon(
                                        Icons.circle_outlined,
                                        color: Color(0x55FFFFFF),
                                        size: 21,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(_startHideTimer);
  }

  void _showSubtitleTracks() {
    final subtitleTracks = _tracks.subtitle;

    showModalBottomSheet(
      context: context,
      backgroundColor: playerPanel,
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
                    color: playerWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(
                    Icons.subtitles_off,
                    color: playerGold,
                  ),
                  title: const Text(
                    'Off',
                    style: TextStyle(color: playerWhite),
                  ),
                  onTap: () => _selectSubtitleTrack(
                    SubtitleTrack.no(),
                  ),
                ),
                ...subtitleTracks.map((track) {
                  return ListTile(
                    leading: const Icon(
                      Icons.subtitles,
                      color: playerGold,
                    ),
                    title: Text(
                      track.title ?? track.language ?? 'Subtitle',
                      style: const TextStyle(color: playerWhite),
                    ),
                    onTap: () => _selectSubtitleTrack(track),
                  );
                }),
                ListTile(
                  leading: const Icon(Icons.add, color: playerGold),
                  title: const Text(
                    'Add External Subtitle',
                    style: TextStyle(color: playerWhite),
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
      backgroundColor: playerPanel,
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
                  color: playerWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Changes the encoded resolution of this same movie.',
                style: TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
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
                    selectedColor: playerGold,
                    backgroundColor: playerBg,
                    labelStyle: TextStyle(
                      color: active ? Colors.black : playerWhite,
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
      backgroundColor: playerPanel,
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
                        color: playerWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.brightness_6_outlined, color: playerGold, size: 20),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'Screen Brightness',
                            style: TextStyle(color: playerWhite, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: playerBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: playerGold.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            '${(sheetBrightness * 100).round()}%',
                            style: const TextStyle(
                              color: playerGoldLight,
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
                        activeTrackColor: playerGold,
                        inactiveTrackColor: Color(0x3DFFFFFF),
                        thumbColor: playerWhite,
                        overlayColor: playerGold.withValues(alpha: 0.18),
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
                        Text('Dim', style: TextStyle(color: Color(0x8AFFFFFF), fontSize: 11)),
                        Text('Bright', style: TextStyle(color: Color(0x8AFFFFFF), fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Playback Speed',
                      style: TextStyle(
                        color: playerGold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: speeds.map((speed) {
                        final selected = _speed == speed;

                        return ChoiceChip(
                          label: Text('${speed}x'),
                          selected: selected,
                          selectedColor: playerGold,
                          backgroundColor: playerBg,
                          labelStyle: TextStyle(
                            color: selected ? Colors.black : playerWhite,
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
                        color: playerGold,
                      ),
                      title: const Text(
                        'Audio language',
                        style: TextStyle(color: playerWhite),
                      ),
                      subtitle: Text(
                        _selectedProviderSource != null
                            ? 'Change language in the provider player'
                            : (_tracks.audio.isEmpty
                                ? 'No alternate audio tracks detected'
                                : _audioTrackLabel(
                                    _tracks.audio[_selectedAudioTrackIndex
                                        .clamp(0, _tracks.audio.length - 1)
                                        .toInt()],
                                    _selectedAudioTrackIndex
                                        .clamp(0, _tracks.audio.length - 1)
                                        .toInt(),
                                  )),
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0x8AFFFFFF),
                      ),
                      onTap: _selectedProviderSource != null
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              _showAudioTracks();
                            },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.subtitles,
                        color: playerGold,
                      ),
                      title: const Text(
                        'Subtitles',
                        style: TextStyle(color: playerWhite),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0x8AFFFFFF),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showSubtitleTracks();
                      },
                    ),
                  ],
                ),
              ),            );
          },
        );
      },
    ).whenComplete(_startHideTimer);
  }

  Widget _centerControls() {
    Widget skipControl({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: playerWhite, size: 27),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        skipControl(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          onPressed: () => _seekBy(-10),
        ),
        const SizedBox(width: 28),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: playerGold,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: playerGold.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            tooltip: _isPlaying ? 'Pause' : 'Play',
            onPressed: _togglePlay,
            iconSize: 43,
            color: playerWhite,
            icon: Icon(
              _isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
        ),
        const SizedBox(width: 28),
        skipControl(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          onPressed: () => _seekBy(10),
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
                  color: playerWhite,
                  fontSize: 11,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    activeTrackColor: playerGold,
                    inactiveTrackColor: const Color(0x4DFFFFFF),
                    thumbColor: playerWhite,
                    overlayColor: playerGold.withValues(alpha: 0.16),
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
                    max: max > 0 ? max : 1,                    onChanged: max > 0
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
                  color: playerWhite,
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
                  color: playerWhite,
                  size: 20,
                ),
              ),
              SizedBox(
                width: 52,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: playerGold,
                    inactiveTrackColor: const Color(0x3DFFFFFF),
                    thumbColor: playerWhite,
                    overlayColor: playerGold.withValues(alpha: 0.16),
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
                  color: playerWhite,
                  size: 20,
                ),
              ),
              TextButton(
                onPressed: _showSettings,
                child: Text(
                  '${_speed}x',
                  style: const TextStyle(
                    color: playerGold,
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
    final audioIndex = _tracks.audio.isEmpty
        ? -1
        : _selectedAudioTrackIndex.clamp(0, _tracks.audio.length - 1).toInt();
    final audioLabel = audioIndex >= 0
        ? _audioTrackLabel(_tracks.audio[audioIndex], audioIndex)
        : 'Audio';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.48),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Back',
              onPressed: () {
                if (_isFullscreen) {
                  _toggleFullscreen();
                } else {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: playerWhite,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.movie.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: playerWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'FLIXORA CINEMA',
                  style: TextStyle(
                    color: playerGoldLight,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.7,
                  ),
                ),
              ],
            ),
          ),
          if (widget.localFilePath == null) ...[
            const SizedBox(width: 5),
            _playerTopAction(
              icon: Icons.high_quality_rounded,
              label: _loadingQualities
                  ? '...'
                  : _selectedQuality == null
                      ? 'Quality'
                      : VideoQualityService.displayName(_selectedQuality!),
              tooltip: 'Video quality',
              enabled: _availableQualities.isNotEmpty,
              onPressed: _showQualitySelector,
            ),
          ],
          if (_selectedProviderSource != null || _tracks.audio.isNotEmpty) ...[
            const SizedBox(width: 3),
            Material(
              color: Colors.black.withValues(alpha: 0.48),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: _selectedProviderSource != null
                    ? 'Audio options in provider player'
                    : 'Audio language: $audioLabel',
                onPressed: _selectedProviderSource != null
                    ? _showProviderAudioHelp
                    : _showAudioTracks,
                icon: const Icon(
                  Icons.audiotrack_rounded,
                  color: playerGoldLight,
                  size: 20,
                ),
              ),
            ),
          ],
          const SizedBox(width: 3),
          Material(
            color: Colors.black.withValues(alpha: 0.48),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Playback settings',
              onPressed: _showSettings,
              icon: const Icon(
                Icons.tune_rounded,
                color: playerWhite,
                size: 21,
              ),
            ),
          ),
          Material(
            color: Colors.black.withValues(alpha: 0.48),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Lock controls',
              onPressed: () {
                setState(() {
                  _isLocked = true;
                  _showControls = false;
                });
                _cancelHideTimer();
              },
              icon: const Icon(
                Icons.lock_outline_rounded,
                color: playerWhite,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerTopAction({
    required IconData icon,
    required String label,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: playerWhite,
          disabledForegroundColor: const Color(0x66FFFFFF),
          backgroundColor: Colors.black.withValues(alpha: 0.42),
          side: BorderSide(
            color: enabled
                ? playerGold.withValues(alpha: 0.68)
                : const Color(0x3DFFFFFF),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled ? playerGoldLight : playerWhite,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
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
              color: playerGold,
              size: 55,
            ),
            const SizedBox(height: 15),
            Text(
              _errorMessage ?? 'Playback error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: playerWhite),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: playerGold,
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
    if (_usingMedia3Fallback && _media3FallbackUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Media3PlayerView(
              key: ValueKey<String>('media3-' + _media3FallbackUrl!),
              url: _media3FallbackUrl!,
              startPositionMs: _media3StartPositionMs,
              controller: _media3Controller,
            ),
          ),
          _media3FallbackActions(),
          if (_media3Error != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                _media3Error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 10),
              ),
            ),
        ],
      );
    }

    final providerSource = _selectedProviderSource;
    if (providerSource != null && !providerSource.isDirectMedia) {
      return ProviderEmbedPlayer(
        key: ValueKey<String>('provider-${providerSource.id}-${providerSource.url}'),
        source: providerSource,
        onClose: _closeProviderSource,
        onNext: () => _tryNextProvider(providerSource),
        onFailure: () => _tryNextProvider(providerSource),
      );
    }

    if (widget.localFilePath == null &&
        !_validVideoUrl &&
        !(providerSource?.isDirectMedia ?? false)) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(22),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline_rounded,
                  color: playerGold, size: 48),
              SizedBox(height: 10),
              Text('Choose a stream below',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: playerWhite,
                      fontSize: 15, fontWeight: FontWeight.w800)),
              SizedBox(height: 5),
              Text('Select an available movie, TV or anime provider to start playback inside FLIXORA.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: Transform.scale(
              alignment: Alignment.center,
              scale: _videoZoom,
              child: Video(
                controller: _videoController,
                // Fullscreen always fills both landscape edges, including
                // the camera-cutout side. Outside fullscreen, preserve the
                // complete frame without cropping.
                fit: _isFullscreen
                    ? BoxFit.cover
                    : (_videoZoom > 1.01
                        ? BoxFit.cover
                        : BoxFit.contain),
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
                  color: playerGold,
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
                color: playerGold,
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
                border: Border.all(color: Color(0x3DFFFFFF)),
              ),
              child: IconButton(
                tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: _toggleFullscreen,
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: playerWhite,
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
                    border: Border.all(color: playerGold.withValues(alpha: 0.45)),
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
                        color: playerGold,
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
                          color: playerWhite,
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

    unawaited(_media3Controller.dispose());
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
                color: playerWhite,
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
                                    color: playerPanel,
                                    child: const Icon(
                                      Icons.movie,
                                      color: playerGold,
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
                            color: playerWhite,
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
        foregroundColor: playerWhite,
        side: const BorderSide(color: Color(0x3DFFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      icon: Icon(icon, color: playerGold, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _audioTrackLabel(AudioTrack track, int index) {
    final title = track.title?.trim() ?? '';
    final language = track.language?.trim() ?? '';

    const languageNames = <String, String>{
      'en': 'English',
      'eng': 'English',
      'english': 'English',
      'hi': 'Hindi',
      'hin': 'Hindi',
      'hindi': 'Hindi',
      'bn': 'বাংলা',
      'ben': 'বাংলা',
      'bengali': 'বাংলা',
      'bangla': 'বাংলা',
      'ta': 'Tamil',
      'tam': 'Tamil',
      'tamil': 'Tamil',
      'te': 'Telugu',
      'tel': 'Telugu',
      'telugu': 'Telugu',
      'kn': 'Kannada',
      'kan': 'Kannada',
      'kannada': 'Kannada',
      'ml': 'Malayalam',
      'mal': 'Malayalam',
      'malayalam': 'Malayalam',
      'ja': 'Japanese',
      'jpn': 'Japanese',
      'japanese': 'Japanese',
      'ko': 'Korean',
      'kor': 'Korean',
      'korean': 'Korean',
      'zh': 'Chinese',
      'zho': 'Chinese',
      'chinese': 'Chinese',
      'es': 'Spanish',
      'spa': 'Spanish',
      'spanish': 'Spanish',
      'fr': 'French',
      'fra': 'French',
      'french': 'French',
      'ar': 'Arabic',
      'ara': 'Arabic',
      'arabic': 'Arabic',
      'ur': 'Urdu',
      'urd': 'Urdu',
      'urdu': 'Urdu',
    };

    String? displayLanguage(String value) {
      final normalized = value.trim().toLowerCase().replaceAll('_', '-');
      if (normalized.isEmpty) return null;
      final firstPart = normalized.split(RegExp(r'[-\s(/]')).first;
      return languageNames[firstPart] ?? languageNames[normalized];
    }

    // Prefer actual language metadata. This handles BCP-47 values such as
    // hi-IN, bn-BD and en-US instead of showing generic "Audio 1" titles.
    final metadataLanguage = displayLanguage(language);
    if (metadataLanguage != null) return metadataLanguage;

    // Some streams put the language in the track title instead.
    final titleLanguage = displayLanguage(title);
    if (titleLanguage != null) return titleLanguage;

    final genericTitle = RegExp(
      r'^(audio|track)(\s*#?\s*\d*)?$',
      caseSensitive: false,
    );
    if (title.isNotEmpty && !genericTitle.hasMatch(title)) return title;

    final normalizedLanguage = language.toLowerCase();
    if (language.isNotEmpty &&
        !{'und', 'unknown', 'unk', 'zxx', 'null'}.contains(normalizedLanguage)) {
      return language;
    }

    return index == 0 ? 'Original / Auto' : 'Audio ${index + 1}';
  }

  Widget _playerResources() {
    final isProviderStream =
        _selectedProviderSource != null && !_selectedProviderSource!.isDirectMedia;
    final providerLanguages = widget.movie.audioLanguages
        .map((language) => language.trim())
        .where((language) => language.isNotEmpty)
        .toSet()
        .toList();
    if (providerLanguages.isEmpty) {
      final originalLabel = _originalAudioLanguageLabel();
      providerLanguages.add(
        originalLabel == 'Not listed' ? 'Original / Auto' : originalLabel,
      );
    }

    final selectedIndex = _tracks.audio.isEmpty
        ? 0
        : _selectedAudioTrackIndex.clamp(0, _tracks.audio.length - 1).toInt();
    final originalLanguage = _originalAudioLanguageLabel().toLowerCase();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: playerPanel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.language_rounded,
                color: playerGoldLight,
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                'Resources',
                style: TextStyle(
                  color: playerWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isProviderStream
                ? 'Available audio languages'
                : 'Select audio language',
            style: const TextStyle(
              color: Color(0x99FFFFFF),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          if (isProviderStream)
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: providerLanguages.map((language) {
                final selected =
                    language.toLowerCase() == originalLanguage;
                return ChoiceChip(
                  label: Text(language),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => _showProviderAudioHelp(),
                  selectedColor: playerGold.withValues(alpha: 0.22),
                  backgroundColor: playerBg,
                  side: BorderSide(
                    color: selected
                        ? playerGold
                        : const Color(0x3DFFFFFF),
                  ),
                  labelStyle: TextStyle(
                    color: selected ? playerGoldLight : playerWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            )
          else if (_tracks.audio.isNotEmpty)
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _tracks.audio.asMap().entries.map((entry) {
                final selected = entry.key == selectedIndex;
                return ChoiceChip(
                  label: Text(_audioTrackLabel(entry.value, entry.key)),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => _selectAudioTrack(
                    entry.value,
                    closeSheet: false,
                  ),
                  selectedColor: playerGold.withValues(alpha: 0.22),
                  backgroundColor: playerBg,
                  side: BorderSide(
                    color: selected
                        ? playerGold
                        : const Color(0x3DFFFFFF),
                  ),
                  labelStyle: TextStyle(
                    color: selected ? playerGoldLight : playerWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            )
          else
            const Text(
              'No alternate audio languages are available.',
              style: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 11,
              ),
            ),
          if (isProviderStream) ...[
            const SizedBox(height: 8),
            const Text(
              'For embedded streams, change the audio track in the video player settings.',
              style: TextStyle(
                color: Color(0x80FFFFFF),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showMovieInfo() async {
    _cancelHideTimer();
    final mediaType = widget.movie.mediaType == 'tv' ? 'tv' : 'movie';
    final castFuture = TmdbService.getCast(
      widget.movie.tmdbId,
      mediaType: mediaType,
    );
    final detailsFuture = _movieDetailsFuture;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: playerPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.76,
        minChildSize: 0.42,
        maxChildSize: 0.94,
        builder: (context, scrollController) => Stack(
          children: [
            SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(17, 46, 17, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: SizedBox(
                          width: 100,
                          height: 148,
                          child: widget.movie.posterUrl.isEmpty
                              ? Container(
                                  color: playerBg,
                                  child: const Icon(
                                    Icons.movie,
                                    color: playerGoldLight,
                                    size: 36,
                                  ),
                                )
                              : FlixoraCachedImage(
                                  imageUrl: widget.movie.posterUrl,
                                  isOnline: _playerIsOnline,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.movie.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: playerWhite,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              [
                                widget.movie.mediaType == 'tv' ? 'TV SERIES' : 'MOVIE',
                                if (widget.movie.year.isNotEmpty) widget.movie.year,
                              ].join('  •  '),
                              style: const TextStyle(
                                color: playerGoldLight,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            FutureBuilder<Map<String, dynamic>>(
                              future: detailsFuture,
                              builder: (context, snapshot) {
                                final data = snapshot.data;
                                if (data == null) return const SizedBox.shrink();
                                final countries = <String>[];
                                final rawCountries = data['production_countries'];
                                if (rawCountries is List) {
                                  for (final item in rawCountries.whereType<Map>()) {
                                    final name = (item['name'] ?? item['iso_3166_1'] ?? '').toString().trim();
                                    if (name.isNotEmpty && !countries.contains(name)) {
                                      countries.add(name);
                                    }
                                  }
                                }
                                if (countries.isEmpty && data['origin_country'] is List) {
                                  countries.addAll(
                                    (data['origin_country'] as List)
                                        .map((item) => item.toString())
                                        .where((item) => item.isNotEmpty),
                                  );
                                }
                                final episodeRuntimes = data['episode_run_time'];
                                final rawRuntime = data['runtime'] ??
                                    (episodeRuntimes is List && episodeRuntimes.isNotEmpty
                                        ? episodeRuntimes.first
                                        : 0);
                                final runtime = _toInt(rawRuntime);
                                final info = <String>[
                                  if (countries.isNotEmpty) 'Country: ${countries.join(', ')}',
                                  if (runtime > 0) '${runtime} min',
                                ];
                                if (info.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    info.join('  •  '),
                                    style: const TextStyle(
                                      color: Color(0xB3FFFFFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (widget.movie.rating > 0) ...[
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: playerGoldLight, size: 19),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${widget.movie.rating.toStringAsFixed(1)}/10',
                                    style: const TextStyle(
                                      color: playerWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'TMDB Rating',
                                    style: TextStyle(
                                      color: Color(0xB3FFFFFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (widget.movie.originCountry.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Country: ${widget.movie.originCountry}',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (widget.movie.originalLanguage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Original language: ${widget.movie.originalLanguage.toUpperCase()}',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (widget.movie.runtime != null && widget.movie.runtime! > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${widget.movie.runtime!.round()} min',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.movie.genres.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: widget.movie.genres.map((genre) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: playerBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: playerGold.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          genre,
                          style: const TextStyle(
                            color: playerGoldLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Movie Info',
                    style: TextStyle(
                      color: playerWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.movie.overview.isEmpty
                        ? 'No description available.'
                        : widget.movie.overview,
                    style: const TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  if (widget.movie.audioLanguages.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Available Audio: ${widget.movie.audioLanguages.join(', ')}',
                      style: const TextStyle(
                        color: playerWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Cast',
                    style: TextStyle(
                      color: playerWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 11),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: castFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 112,
                          child: Center(
                            child: CircularProgressIndicator(color: playerGoldLight),
                          ),
                        );
                      }
                      final cast = snapshot.data ?? const <Map<String, dynamic>>[];
                      if (cast.isEmpty) {
                        return const Text(
                          'Cast photos are not available for this title.',
                          style: TextStyle(
                            color: Color(0xB3FFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                      return SizedBox(
                        height: 142,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: cast.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 11),
                          itemBuilder: (context, index) {
                            final person = cast[index];
                            final profile = (person['profile_path'] ?? '').toString();
                            final name = (person['name'] ?? 'Cast member').toString();
                            final character = (person['character'] ?? '').toString();
                            return SizedBox(
                              width: 78,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 72,
                                      height: 88,
                                      child: profile.isEmpty
                                          ? Container(
                                              color: playerBg,
                                              child: const Icon(
                                                Icons.person,
                                                color: playerGoldLight,
                                                size: 34,
                                              ),
                                            )
                                          : FlixoraCachedImage(
                                              imageUrl: '${imageBase}w185$profile',
                                              isOnline: _playerIsOnline,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: playerWhite,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (character.isNotEmpty)
                                    Text(
                                      character,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xB3FFFFFF),
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 5,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: playerBg,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Close movie information',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: playerWhite,
                    size: 19,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    _startHideTimer();
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
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.movie.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: playerWhite,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Movie information',
                      onPressed: _showMovieInfo,
                      icon: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, color: playerGoldLight, size: 17),
                          Icon(Icons.keyboard_arrow_down_rounded, color: playerGoldLight, size: 21),
                        ],
                      ),
                    ),
                  ],
                ),
                _playerMetadata(),
                const SizedBox(height: 16),
                _providerSelector(),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailAction(Icons.playlist_add, 'Add to list', widget.onSave),
                    _detailAction(
                      Icons.share_outlined,
                      'Share',
                      () => Share.share(
                        '${widget.movie.title} (${widget.movie.year}) on FLIXORA',
                      ),
                    ),
                    _detailAction(Icons.download_outlined, 'Download', widget.onDownload),
                    _detailAction(
                      Icons.video_library_outlined,
                      'View downloads',
                      widget.onViewDownloads,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _playerResources(),
                _tvEpisodeSelector(),
                const SizedBox(height: 16),
                const Text(
                  'For You',
                  style: TextStyle(
                    color: playerWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
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
        backgroundColor: playerBg,
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