import 'dart:convert';

import 'package:http/http.dart' as http;

/// GitHub-hosted registry for remote Stremio subtitle add-ons.
/// Only HTTPS subtitle resources are queried; add-on executable code is never downloaded.
class FlixoraSubtitleExtension {
  const FlixoraSubtitleExtension({
    required this.id,
    required this.name,
    required this.manifestUrl,
    required this.enabled,
    required this.priority,
    required this.languages,
    required this.types,
  });

  final String id;
  final String name;
  final Uri manifestUrl;
  final bool enabled;
  final int priority;
  final List<String> languages;
  final List<String> types;

  factory FlixoraSubtitleExtension.fromJson(Map<String, dynamic> json) {
    final uri = Uri.tryParse((json['manifestUrl'] ?? '').toString());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Extension manifest must use public HTTPS.');
    }
    final id = (json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty) {
      throw const FormatException('Extension id and name are required.');
    }
    return FlixoraSubtitleExtension(
      id: id,
      name: name,
      manifestUrl: uri,
      enabled: json['enabled'] == true,
      priority: (json['priority'] as num?)?.toInt() ?? 100,
      languages: _strings(json['languages']),
      types: _strings(json['types']),
    );
  }

  static List<String> _strings(dynamic value) => value is List
      ? value.map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty).toList(growable: false)
      : const <String>[];
}

class FlixoraSubtitleExtensionResult {
  const FlixoraSubtitleExtensionResult({
    required this.extensionId,
    required this.extensionName,
    required this.id,
    required this.url,
    required this.language,
    required this.label,
  });

  final String extensionId;
  final String extensionName;
  final String id;
  final Uri url;
  final String language;
  final String label;
}

class FlixoraSubtitleExtensionManager {
  FlixoraSubtitleExtensionManager({http.Client? client, Uri? registryUrl})
      : _client = client ?? http.Client(),
        registryUrl = registryUrl ?? defaultRegistryUrl;

  static final Uri defaultRegistryUrl = Uri.parse(
    'https://raw.githubusercontent.com/shohanur2/FLIXORA-BOX/'
    'feat/github-stremio-subtitle-extensions/subtitle-extensions/registry.json',
  );

  final http.Client _client;
  final Uri registryUrl;

  Future<List<FlixoraSubtitleExtension>> loadExtensions() async {
    _requireHttps(registryUrl);
    final response = await _client.get(registryUrl,
        headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Subtitle extension registry HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['schemaVersion'] != 1 ||
        decoded['protocol'] != 'stremio-addon-v1' ||
        decoded['addons'] is! List) {
      throw const FormatException('Invalid subtitle extension registry.');
    }
    final extensions = <FlixoraSubtitleExtension>[];
    for (final raw in decoded['addons'] as List) {
      if (raw is! Map) continue;
      try {
        final extension = FlixoraSubtitleExtension.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (extension.enabled) extensions.add(extension);
      } catch (_) {
        // Ignore one invalid entry and continue with the remaining add-ons.
      }
    }
    extensions.sort((a, b) => a.priority.compareTo(b.priority));
    return extensions;
  }

  Future<List<FlixoraSubtitleExtensionResult>> search({
    required String imdbId,
    required String mediaType,
    required int season,
    required int episode,
    required List<String> languages,
  }) async {
    final id = imdbId.trim();
    if (!RegExp(r'^tt[0-9]{5,12}$').hasMatch(id)) return const [];
    final type = mediaType == 'tv' || mediaType == 'series' ? 'series' : 'movie';
    if (type == 'series' && (season < 0 || episode < 1)) return const [];

    final requested = languages.map(_normalizeLanguage)
        .where((value) => value.isNotEmpty).toSet();
    final extensions = await loadExtensions();
    final results = <FlixoraSubtitleExtensionResult>[];

    for (final extension in extensions) {
      if (extension.types.isNotEmpty && !extension.types.contains(type)) continue;
      if (extension.languages.isNotEmpty && requested.isNotEmpty &&
          !extension.languages.any(requested.contains)) continue;
      try {
        final manifest = await _loadManifest(extension);
        if (!_supportsSubtitleResource(manifest, type, id)) continue;

        // Stremio's series subtitle id format is IMDb-ID:season:episode.
        final resourceId = type == 'series' ? '$id:$season:$episode' : id;
        final endpoint = _subtitleEndpoint(extension.manifestUrl, type, resourceId);
        final response = await _client.get(endpoint,
            headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is! Map || payload['subtitles'] is! List) continue;

        for (final raw in payload['subtitles'] as List) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final subtitleUrl = Uri.tryParse((item['url'] ?? '').toString());
          if (subtitleUrl == null || subtitleUrl.scheme != 'https' ||
              subtitleUrl.host.isEmpty || subtitleUrl.userInfo.isNotEmpty) {
            continue;
          }
          final language = _normalizeLanguage(
            (item['lang'] ?? '').toString(),
          );
          if (language.isEmpty ||
              (requested.isNotEmpty && !requested.contains(language))) {
            continue;
          }
          results.add(FlixoraSubtitleExtensionResult(
            extensionId: extension.id,
            extensionName: extension.name,
            id: (item['id'] ?? '').toString(),
            url: subtitleUrl,
            language: language,
            label: (item['label'] ?? item['name'] ?? extension.name).toString(),
          ));
        }
      } catch (error) {
        // Per-extension failover: a failed add-on cannot block the next one.
        continue;
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> _loadManifest(
      FlixoraSubtitleExtension extension) async {
    _requireHttps(extension.manifestUrl);
    final response = await _client.get(extension.manifestUrl,
        headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Add-on manifest HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        (decoded['id'] ?? '').toString() != extension.id ||
        decoded['resources'] is! List) {
      throw const FormatException('Invalid Stremio add-on manifest.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  bool _supportsSubtitleResource(
      Map<String, dynamic> manifest, String type, String imdbId) {
    final resources = manifest['resources'] as List;
    var found = false;
    for (final resource in resources) {
      if (resource == 'subtitles') {
        found = true;
        break;
      }
      if (resource is Map && resource['name'] == 'subtitles') {
        final types = resource['types'];
        final prefixes = resource['idPrefixes'];
        if (types is List && !types.contains(type)) continue;
        if (prefixes is List && prefixes.isNotEmpty &&
            !prefixes.any((p) => imdbId.startsWith(p.toString()))) continue;
        found = true;
        break;
      }
    }
    if (!found) return false;
    final types = manifest['types'];
    if (types is List && !types.contains(type)) return false;
    final prefixes = manifest['idPrefixes'];
    if (prefixes is List && prefixes.isNotEmpty &&
        !prefixes.any((p) => imdbId.startsWith(p.toString()))) return false;
    return true;
  }

  Uri _subtitleEndpoint(Uri manifestUrl, String type, String id) {
    // Resolve against the directory containing manifest.json, preserving
    // add-ons hosted below a path such as /stremio/manifest.json.
    final base = manifestUrl.resolve('.');
    return base.resolve('subtitles/$type/${Uri.encodeComponent(id)}.json');
  }

  static String _normalizeLanguage(String value) {
    final code = value.trim().toLowerCase().split(RegExp('[-_]')).first;
    const aliases = <String, String>{
      'eng': 'en', 'ben': 'bn', 'beng': 'bn', 'hin': 'hi', 'urd': 'ur',
      'ara': 'ar', 'spa': 'es', 'fre': 'fr', 'fra': 'fr',
      'ger': 'de', 'deu': 'de', 'por': 'pt', 'rus': 'ru',
      'jpn': 'ja', 'kor': 'ko', 'chi': 'zh', 'zho': 'zh',
      'tur': 'tr', 'ita': 'it', 'nld': 'nl', 'pol': 'pl',
      'tha': 'th', 'ind': 'id', 'msa': 'ms', 'fas': 'fa',
    };
    return aliases[code] ?? code;
  }

  static void _requireHttps(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Only public HTTPS extension URLs are allowed.');
    }
  }

  void dispose() => _client.close();
}
