import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OmdbMetadata {
  const OmdbMetadata({
    required this.imdbRating,
    required this.metascore,
    required this.rated,
    required this.runtime,
    required this.awards,
    required this.imdbVotes,
    required this.boxOffice,
    required this.country,
    required this.language,
  });

  final String imdbRating;
  final String metascore;
  final String rated;
  final String runtime;
  final String awards;
  final String imdbVotes;
  final String boxOffice;
  final String country;
  final String language;

  factory OmdbMetadata.fromJson(Map<String, dynamic> json) {
    String value(String key) {
      final raw = (json[key] ?? '').toString().trim();
      return raw == 'N/A' ? '' : raw;
    }

    return OmdbMetadata(
      imdbRating: value('imdbRating'),
      metascore: value('Metascore'),
      rated: value('Rated'),
      runtime: value('Runtime'),
      awards: value('Awards'),
      imdbVotes: value('imdbVotes'),
      boxOffice: value('BoxOffice'),
      country: value('Country'),
      language: value('Language'),
    );
  }

  bool get hasContent => <String>[
        imdbRating, metascore, rated, runtime, awards, imdbVotes,
        boxOffice, country, language,
      ].any((value) => value.isNotEmpty);
}

class WatchmodeSource {
  const WatchmodeSource({
    required this.name,
    required this.type,
    required this.region,
    required this.format,
    required this.price,
    required this.webUrl,
  });

  final String name;
  final String type;
  final String region;
  final String format;
  final String price;
  final String webUrl;

  factory WatchmodeSource.fromJson(Map<String, dynamic> json) {
    String value(String key) {
      final raw = (json[key] ?? '').toString().trim();
      return raw == 'null' || raw == 'N/A' ? '' : raw;
    }

    return WatchmodeSource(
      name: value('name'),
      type: value('type'),
      region: value('region'),
      format: value('format'),
      price: value('price'),
      webUrl: value('web_url'),
    );
  }
}

class TasteDiveSuggestion {
  const TasteDiveSuggestion({
    required this.name,
    required this.type,
    required this.description,
  });

  final String name;
  final String type;
  final String description;

  factory TasteDiveSuggestion.fromJson(Map<String, dynamic> json) {
    return TasteDiveSuggestion(
      name: (json['Name'] ?? '').toString().trim(),
      type: (json['Type'] ?? '').toString().trim(),
      description: (json['wTeaser'] ?? '').toString().trim(),
    );
  }
}

class ExternalCatalogData {
  const ExternalCatalogData({
    this.omdb,
    this.watchmode = const <WatchmodeSource>[],
    this.similar = const <TasteDiveSuggestion>[],
  });

  final OmdbMetadata? omdb;
  final List<WatchmodeSource> watchmode;
  final List<TasteDiveSuggestion> similar;

  bool get isEmpty =>
      (omdb == null || !omdb!.hasContent) &&
      watchmode.isEmpty &&
      similar.isEmpty;
}

/// Optional metadata/discovery integrations. These APIs do not provide
/// playable movie streams; FLIXORA's existing Player sources remain separate.
class ExternalCatalogService {
  ExternalCatalogService._();

  static const String omdbApiKey = String.fromEnvironment('OMDB_API_KEY');
  static const String watchmodeApiKey =
      String.fromEnvironment('WATCHMODE_API_KEY');
  static const String tasteDiveApiKey =
      String.fromEnvironment('TASTEDIVE_API_KEY');

  static bool get hasAnyConfigured =>
      omdbApiKey.isNotEmpty ||
      watchmodeApiKey.isNotEmpty ||
      tasteDiveApiKey.isNotEmpty;

  static Future<ExternalCatalogData> load({
    required String title,
    required String year,
    required String mediaType,
    required int tmdbId,
    String region = 'BD',
  }) async {
    final omdbFuture = omdbApiKey.isEmpty
        ? Future<OmdbMetadata?>.value(null)
        : getOmdb(title: title, year: year, mediaType: mediaType);
    final watchmodeFuture = watchmodeApiKey.isEmpty || tmdbId <= 0
        ? Future<List<WatchmodeSource>>.value(const <WatchmodeSource>[])
        : getWatchmodeSources(
            tmdbId: tmdbId,
            mediaType: mediaType,
            region: region,
          );
    final similarFuture = tasteDiveApiKey.isEmpty
        ? Future<List<TasteDiveSuggestion>>.value(
            const <TasteDiveSuggestion>[],
          )
        : getSimilar(title: title, mediaType: mediaType);

    final values = await Future.wait<Object?>([
      omdbFuture,
      watchmodeFuture,
      similarFuture,
    ]);

    return ExternalCatalogData(
      omdb: values[0] as OmdbMetadata?,
      watchmode: values[1] as List<WatchmodeSource>,
      similar: values[2] as List<TasteDiveSuggestion>,
    );
  }

  static Future<OmdbMetadata?> getOmdb({
    required String title,
    required String year,
    required String mediaType,
  }) async {
    if (omdbApiKey.trim().isEmpty || title.trim().isEmpty) return null;
    try {
      final parameters = <String, String>{
        'apikey': omdbApiKey,
        't': title.trim(),
        'plot': 'short',
        'type': mediaType == 'tv' ? 'series' : 'movie',
      };
      if (RegExp(r'^\\d{4}$').hasMatch(year.trim())) {
        parameters['y'] = year.trim();
      }
      final response = await http
          .get(Uri.https('www.omdbapi.com', '/', parameters))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map || json['Response']?.toString() != 'True') return null;
      return OmdbMetadata.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  static Future<List<WatchmodeSource>> getWatchmodeSources({
    required int tmdbId,
    required String mediaType,
    String region = 'BD',
  }) async {
    if (watchmodeApiKey.trim().isEmpty || tmdbId <= 0) {
      return const <WatchmodeSource>[];
    }
    final type = mediaType == 'tv' ? 'tv' : 'movie';
    try {
      final response = await http
          .get(
            Uri.https(
              'api.watchmode.com',
              '/v1/title/$type-$tmdbId/sources/',
              <String, String>{
                'apiKey': watchmodeApiKey,
                if (region.trim().isNotEmpty)
                  'regions': region.trim().toUpperCase(),
              },
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const <WatchmodeSource>[];
      final json = jsonDecode(response.body);
      if (json is! List) return const <WatchmodeSource>[];
      final sources = json
          .whereType<Map>()
          .map((item) => WatchmodeSource.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((source) => source.name.isNotEmpty)
          .toList();
      sources.sort((a, b) {
        const order = <String, int>{
          'sub': 0,
          'free': 1,
          'tve': 2,
          'rent': 3,
          'buy': 4,
        };
        return (order[a.type.toLowerCase()] ?? 9)
            .compareTo(order[b.type.toLowerCase()] ?? 9);
      });
      return sources;
    } catch (_) {
      return const <WatchmodeSource>[];
    }
  }

  static Future<List<TasteDiveSuggestion>> getSimilar({
    required String title,
    required String mediaType,
  }) async {
    if (tasteDiveApiKey.trim().isEmpty || title.trim().isEmpty) {
      return const <TasteDiveSuggestion>[];
    }
    try {
      final kind = mediaType == 'tv' ? 'show' : 'movie';
      final response = await http
          .get(
            Uri.https(
              'tastedive.com',
              '/api/similar',
              <String, String>{
                'k': tasteDiveApiKey,
                'q': '$kind:${title.trim()}',
                'type': kind,
                'info': '1',
                'limit': '8',
              },
            ),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const <TasteDiveSuggestion>[];
      final json = jsonDecode(response.body);
      if (json is! Map || json['Similar'] is! Map) {
        return const <TasteDiveSuggestion>[];
      }
      final rows = (json['Similar'] as Map)['Results'];
      if (rows is! List) return const <TasteDiveSuggestion>[];
      return rows
          .whereType<Map>()
          .map((item) => TasteDiveSuggestion.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.name.isNotEmpty)
          .take(8)
          .toList();
    } catch (_) {
      return const <TasteDiveSuggestion>[];
    }
  }
}

class ExternalCatalogSection extends StatefulWidget {
  const ExternalCatalogSection({
    super.key,
    required this.title,
    required this.year,
    required this.mediaType,
    required this.tmdbId,
  });

  final String title;
  final String year;
  final String mediaType;
  final int tmdbId;

  @override
  State<ExternalCatalogSection> createState() =>
      _ExternalCatalogSectionState();
}

class _ExternalCatalogSectionState extends State<ExternalCatalogSection> {
  late final Future<ExternalCatalogData> _future;

  @override
  void initState() {
    super.initState();
    _future = ExternalCatalogService.load(
      title: widget.title,
      year: widget.year,
      mediaType: widget.mediaType,
      tmdbId: widget.tmdbId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ExternalCatalogService.hasAnyConfigured) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<ExternalCatalogData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'More from our data partners',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (data.omdb != null && data.omdb!.hasContent) ...[
                const SizedBox(height: 10),
                _ExternalPanel(
                  title: 'OMDb details',
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 9,
                    children: [
                      if (data.omdb!.imdbRating.isNotEmpty)
                        _ExternalMetric(
                          label: 'IMDb',
                          value: data.omdb!.imdbRating,
                        ),
                      if (data.omdb!.metascore.isNotEmpty)
                        _ExternalMetric(
                          label: 'Metascore',
                          value: data.omdb!.metascore,
                        ),
                      if (data.omdb!.rated.isNotEmpty)
                        _ExternalMetric(
                          label: 'Rated',
                          value: data.omdb!.rated,
                        ),
                      if (data.omdb!.runtime.isNotEmpty)
                        _ExternalMetric(
                          label: 'Runtime',
                          value: data.omdb!.runtime,
                        ),
                      if (data.omdb!.imdbVotes.isNotEmpty)
                        _ExternalMetric(
                          label: 'Votes',
                          value: data.omdb!.imdbVotes,
                        ),
                      if (data.omdb!.boxOffice.isNotEmpty)
                        _ExternalMetric(
                          label: 'Box office',
                          value: data.omdb!.boxOffice,
                        ),
                    ],
                  ),
                ),
              ],
              if (data.watchmode.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ExternalPanel(
                  title: 'Where to watch · Bangladesh',
                  child: Column(
                    children: data.watchmode.take(8).map((source) {
                      final detail = <String>[
                        if (source.type.isNotEmpty)
                          source.type.toUpperCase(),
                        if (source.format.isNotEmpty) source.format,
                        if (source.price.isNotEmpty) source.price,
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.live_tv_outlined,
                              color: Color(0xFFD6AD45),
                              size: 17,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                source.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              if (data.similar.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ExternalPanel(
                  title: 'You may also like',
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: data.similar.map((item) {
                      return Chip(
                        label: Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                        backgroundColor: const Color(0xFF292929),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Text(
                  'Availability and recommendations are informational only; they do not provide playback streams.',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExternalPanel extends StatelessWidget {
  const _ExternalPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF191919),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFF6670),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _ExternalMetric extends StatelessWidget {
  const _ExternalMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
