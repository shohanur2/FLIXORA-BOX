import 'dart:convert';

import 'package:http/http.dart' as http;

/// A TMDB streaming service that can be browsed as its own FLIXORA section.
class OttProvider {
  const OttProvider({
    required this.id,
    required this.name,
    required this.logoPath,
    required this.displayPriority,
  });

  final int id;
  final String name;
  final String logoPath;
  final int displayPriority;

  String get logoUrl => logoPath.isEmpty
      ? ''
      : 'https://image.tmdb.org/t/p/w185' + logoPath;

  factory OttProvider.fromJson(Map<String, dynamic> json) {
    final rawId = json['provider_id'];
    final rawPriority = json['display_priority'];
    return OttProvider(
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0,
      name: (json['provider_name'] ?? '').toString().trim(),
      logoPath: (json['logo_path'] ?? '').toString().trim(),
      displayPriority: rawPriority is num
          ? rawPriority.toInt()
          : int.tryParse('$rawPriority') ?? 9999,
    );
  }
}

class OttCatalogService {
  OttCatalogService._();

  static const String _base = 'https://api.themoviedb.org/3';

  /// Keep the most requested global services first when TMDB returns them.
  static const List<int> _featuredOrder = <int>[
    8, 9, 337, 350, 384, 1899, 283, 15, 531, 386,
    232, 315, 158, 237, 233,
  ];

  static List<OttProvider> sortProviders(Iterable<OttProvider> providers) {
    final unique = <int, OttProvider>{};
    for (final provider in providers) {
      if (provider.id > 0 && provider.name.isNotEmpty) {
        unique.putIfAbsent(provider.id, () => provider);
      }
    }
    final items = unique.values.toList();
    items.sort((a, b) {
      final aFeatured = _featuredOrder.indexOf(a.id);
      final bFeatured = _featuredOrder.indexOf(b.id);
      final aPinned = aFeatured >= 0;
      final bPinned = bFeatured >= 0;
      if (aPinned && bPinned) return aFeatured.compareTo(bFeatured);
      if (aPinned) return -1;
      if (bPinned) return 1;
      final priority = a.displayPriority.compareTo(b.displayPriority);
      return priority != 0 ? priority : a.name.compareTo(b.name);
    });
    return items;
  }

  static Future<List<OttProvider>> getProviders({
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('TMDB API key is not configured.');
    }

    Future<List<OttProvider>> load(String mediaType) async {
      final uri = Uri.parse(_base + '/watch/providers/' + mediaType)
          .replace(queryParameters: {
        'api_key': apiKey,
        'language': 'en-US',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('TMDB could not load streaming platforms.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['results'] as List? ?? [])
          .whereType<Map>()
          .map((item) => OttProvider.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    }

    final results = await Future.wait([
      load('movie'),
      load('tv'),
    ]);
    return sortProviders([...results[0], ...results[1]]);
  }

  static Future<List<Map<String, dynamic>>> getProviderTitles({
    required String apiKey,
    required int providerId,
    required String region,
    String mediaFilter = 'All',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('TMDB API key is not configured.');
    }
    if (providerId <= 0) return const [];

    final normalizedRegion = region.trim().toUpperCase();
    final mediaTypes = mediaFilter == 'Movies'
        ? const ['movie']
        : mediaFilter == 'TV Series'
            ? const ['tv']
            : const ['movie', 'tv'];

    Future<List<Map<String, dynamic>>> load(String mediaType) async {
      final pages = await Future.wait(
        List<int>.generate(3, (index) => index + 1).map((page) async {
          final uri = Uri.parse(_base + '/discover/' + mediaType)
              .replace(queryParameters: {
            'api_key': apiKey,
            'language': 'en-US',
            'page': page.toString(),
            'sort_by': 'popularity.desc',
            'watch_region': normalizedRegion,
            'with_watch_providers': providerId.toString(),
            'with_watch_monetization_types': 'flatrate|free|ads',
          });
          try {
            http.Response? response;
            for (var attempt = 0; attempt < 3; attempt++) {
              response = await http.get(uri).timeout(const Duration(seconds: 20));
              if (response.statusCode == 200 ||
                  (response.statusCode != 429 && response.statusCode < 500) ||
                  attempt == 2) {
                break;
              }
              await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
            }
            if (response.statusCode != 200) return <Map<String, dynamic>>[];
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            return (data['results'] as List? ?? [])
                .whereType<Map>()
                .map((item) {
                  final result = Map<String, dynamic>.from(item);
                  result['media_type'] = mediaType;
                  return result;
                })
                .toList();
          } catch (_) {
            return <Map<String, dynamic>>[];
          }
        }),
      );
      return pages.expand((items) => items).toList();
    }

    final results = await Future.wait(mediaTypes.map(load));
    final titles = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final group in results) {
      for (final title in group) {
        final id = title['id'];
        final mediaType = title['media_type'];
        final key = mediaType.toString() + ':' + id.toString();
        if (seen.add(key)) titles.add(title);
      }
    }
    titles.sort((a, b) {
      final aPopularity = (a['popularity'] as num?)?.toDouble() ?? 0;
      final bPopularity = (b['popularity'] as num?)?.toDouble() ?? 0;
      return bPopularity.compareTo(aPopularity);
    });
    return titles;
  }
}
