import '../native/sparkbox_core.dart';

/// Single entry point for FLIXORA's MovieBox/WeFeed content system.
///
/// The native Rust core owns request signing, guest tokens, mobile/H5
/// fallback, parsing, stream resolution and subtitle discovery. Flutter
/// receives normalized JSON maps and remains responsible for UI, playback,
/// caching and downloads.
class MovieBoxService {
  MovieBoxService._();

  static Future<Map<String, dynamic>> version() => SparkBoxCore.version();

  static Future<void> enableSafeContentFilter() =>
      SparkBoxCore.setBlockAdult(true);

  static Future<List<Map<String, dynamic>>> home() => SparkBoxCore.home();

  static Future<List<String>> suggest(String query) =>
      SparkBoxCore.suggest(query);

  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _searchCache = {};

  static Future<Map<String, dynamic>> search(
    String query, {
    int page = 1,
    int perPage = 20,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Future<Map<String, dynamic>>.value(
        <String, dynamic>{'items': <dynamic>[]},
      );
    }
    final key = '${normalizedQuery.toLowerCase()}:$page:$perPage';
    return _remember(
      _searchCache,
      key,
      const Duration(minutes: 2),
      () => SparkBoxCore.search(
        normalizedQuery,
        page: page,
        perPage: perPage,
      ),
    );
  }

  static Future<Map<String, dynamic>> detail(
    Map<String, dynamic> item,
  ) =>
      SparkBoxCore.detailRich(item);

  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _playDetailCache = {};
  static final Map<String, _MovieBoxCacheEntry<List<Map<String, dynamic>>>>
      _seasonsCache = {};
  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _streamsCache = {};

  static String _subjectId(Map<String, dynamic> item) =>
      (item['id'] ?? item['subjectId'] ?? item['subject_id'] ?? '')
          .toString()
          .trim();

  static Future<T> _remember<T>(
    Map<String, _MovieBoxCacheEntry<T>> cache,
    String key,
    Duration ttl,
    Future<T> Function() load,
  ) {
    final now = DateTime.now();
    final existing = cache[key];
    if (existing != null && now.difference(existing.createdAt) < ttl) {
      return existing.future;
    }

    final future = load();
    final entry = _MovieBoxCacheEntry<T>(
      createdAt: now,
      future: future,
    );
    cache[key] = entry;
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(cache[key], entry)) cache.remove(key);
      },
    );
    return future;
  }

  static Future<Map<String, dynamic>> playDetail(
    Map<String, dynamic> item,
  ) {
    final id = _subjectId(item);
    if (id.isEmpty) return SparkBoxCore.playDetail(item);
    return _remember(
      _playDetailCache,
      id,
      const Duration(minutes: 2),
      () => SparkBoxCore.playDetail(item),
    );
  }

  static Future<List<Map<String, dynamic>>> seasons(String subjectId) =>
      _remember(
        _seasonsCache,
        subjectId,
        const Duration(minutes: 5),
        () => SparkBoxCore.seasons(subjectId),
      );

  static Future<Map<String, dynamic>> streams(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required bool isSeries,
  }) {
    final subject = (detail['subjectId'] ??
            detail['subject_id'] ??
            detail['id'] ??
            detail['detailPath'] ??
            detail.toString())
        .toString();
    final key = '$subject:$season:$episode:$isSeries';
    return _remember(
      _streamsCache,
      key,
      const Duration(seconds: 30),
      () => SparkBoxCore.streams(
        detail,
        season: season,
        episode: episode,
        isSeries: isSeries,
      ),
    );
  }

  /// Resolve the first playable item while the movie details screen is open.
  /// The player and download actions reuse these short-lived requests.
  static Future<void> prewarm(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) async {
    final id = _subjectId(item);
    if (id.isEmpty) return;

    try {
      final requests = <Future<dynamic>>[playDetail(item)];
      if (isSeries) requests.add(seasons(id));
      final resolved = await Future.wait<dynamic>(requests);
      final detail = Map<String, dynamic>.from(resolved.first as Map);

      var season = 0;
      var episode = 0;
      if (isSeries) {
        final availableSeasons =
            resolved[1] as List<Map<String, dynamic>>;
        if (availableSeasons.isEmpty) return;
        final firstSeason = availableSeasons.first;
        season = int.tryParse((firstSeason['se'] ?? '').toString()) ?? 0;
        final episodes = firstSeason['episodes'] as List? ?? const [];
        if (episodes.isNotEmpty) {
          episode = int.tryParse(episodes.first.toString()) ?? 0;
        }
        if (season <= 0) return;
      }

      await streams(
        detail,
        season: season,
        episode: episode,
        isSeries: isSeries,
      );
    } catch (_) {
      // Prefetch is opportunistic; the player still reports real failures.
    }
  }
}

class _MovieBoxCacheEntry<T> {
  const _MovieBoxCacheEntry({
    required this.createdAt,
    required this.future,
  });

  final DateTime createdAt;
  final Future<T> future;
}
