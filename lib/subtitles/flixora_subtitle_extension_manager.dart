import 'dart:convert';

import 'package:http/http.dart' as http;

/// GitHub-hosted, Stremio-compatible subtitle add-on discovery.
///
/// Add-ons are remote HTTPS APIs, never downloaded executable code.
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
    final rawUrl = (json['manifestUrl'] ?? '').toString();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Extension manifest must use HTTPS.');
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
      languages: _stringList(json['languages']),
      types: _stringList(json['types']),
    );
  }

  static List<String> _stringList(dynamic value) => value is List
      ? value.map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty).toList(growable: false)
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

/// Reads the GitHub registry and queries only Stremio subtitle resources.
class FlixoraSubtitleExtensionManager {
  FlixoraSubtitleExtensionManager({
    http.Client? client,
    Uri? registryUrl,
  })  : _client = client ?? http.Client(),
        registryUrl = registryUrl ?? defaultRegistryUrl;

  static final Uri defaultRegistryUrl = Uri.parse(
    'https://raw.githubusercontent.com/shohanur2/FLIXORA-BOX/'
    'feat/github-stremio-subtitle-extensions/subtitle-extensions/registry.json',
  );

  final http.Client _client;
  final Uri registryUrl;

  Future<List<FlixoraSubtitleExtension>> loadExtensions() async {
    _requireHttps(registryUrl);
    final response = await _client.get(
      registryUrl,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Subtitle extension registry HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['schemaVersion'] != 1 ||
        decoded['protocol'] != 'stremio-addon-v1') {
      throw const FormatException('Unsupported subtitle extension registry.');
    }
    final raw = decoded['addons'];
    if (raw is! List) {
      throw const FormatException('Subtitle extension registry has no add-on list.');
    }
    final extensions = <FlixoraSubtitleExtension>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final extension = FlixoraSubtitleExtension.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (extension.enabled) extensions.add(extension);
      } catch (_) {
        // One malformed registry entry must not disable other extensions.
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
    final normalizedImdbId = imdbId.trim();
    if (!RegExp(r'^tt[0-9]{5,12}    final type = mediaType == 'tv' || mediaType == 'series' ? 'series' : 'movie';
    final requestedLanguages = languages.map(_normalizeLanguage)
        .where((value) => value.isNotEmpty).toSet();
    final extensions = await loadExtensions();
    final results = <FlixoraSubtitleExtensionResult>[];

    for (final extension in extensions) {
      if (extension.types.isNotEmpty && !extension.types.contains(type)) continue;
      if (extension.languages.isNotEmpty &&
          requestedLanguages.isNotEmpty &&
          !extension.languages.any(requestedLanguages.contains)) continue;
      try {
        final manifest = await _loadManifest(extension);
        if (!_supportsSubtitleResource(manifest, type)) continue;
        final id = type == 'series'
            ? '$normalizedImdbId:$season:$episode'
            : normalizedImdbId;
        final endpoint = _subtitleEndpoint(extension.manifestUrl, type, id);
        final response = await _client.get(
          endpoint,
          headers: const {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is! Map || payload['subtitles'] is! List) continue;
        for (final raw in payload['subtitles'] as List) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final subtitleUrl = Uri.tryParse((item['url'] ?? '').toString());
          if (subtitleUrl == null || subtitleUrl.scheme != 'https' ||
              subtitleUrl.host.isEmpty) continue;
          final language = _normalizeLanguage(item['lang']?.toString() ?? '');
          if (language.isEmpty ||
              (requestedLanguages.isNotEmpty &&
               !requestedLanguages.contains(language))) continue;
          results.add(FlixoraSubtitleExtensionResult(
            extensionId: extension.id,
            extensionName: extension.name,
            id: (item['id'] ?? '').toString(),
            url: subtitleUrl,
            language: language,
            label: (item['label'] ?? extension.name).toString(),
          ));
        }
      } catch (_) {
        // Fail over: a broken or unavailable add-on cannot block the next one.
        continue;
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> _loadManifest(
    FlixoraSubtitleExtension extension,
  ) async {
    _requireHttps(extension.manifestUrl);
    final response = await _client.get(
      extension.manifestUrl,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Add-on manifest HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        (decoded['id'] ?? '').toString() != extension.id ||
        decoded['resources'] is! List) {
      throw const FormatException('Invalid Stremio subtitle add-on manifest.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  bool _supportsSubtitleResource(Map<String, dynamic> manifest, String type) {
    final resources = manifest['resources'] as List;
    final subtitleResource = resources.where((resource) =>
        resource == 'subtitles' ||
        (resource is Map && resource['name'] == 'subtitles')).toList();
    if (subtitleResource.isEmpty) return false;
    for (final resource in subtitleResource) {
      if (resource is Map) {
        final resourceTypes = resource['types'];
        if (resourceTypes is List && !resourceTypes.contains(type)) continue;
        final prefixes = resource['idPrefixes'];
        if (prefixes is List && prefixes.isNotEmpty &&
            !prefixes.any((prefix) => 'tt0000000'.startsWith(prefix.toString()))) {
          continue;
        }
        return true;
      }
      final prefixes = manifest['idPrefixes'];
      if (prefixes is List && prefixes.isNotEmpty &&
          !prefixes.any((prefix) => 'tt0000000'.startsWith(prefix.toString()))) {
        continue;
      }
      return true;
    }
    return false;
    final rawTypes = manifest['types'];
    if (rawTypes is List && !rawTypes.contains(type)) return false;
    return true;
  }

  Uri _subtitleEndpoint(Uri manifestUrl, String type, String id) {
    final base = manifestUrl.resolve('.');
    return base.resolve(
      'subtitles/$type/${Uri.encodeComponent(id)}.json',
    );
  }

  static String _normalizeLanguage(String value) {
    final language = value.trim().toLowerCase().split(RegExp('[-_]')).first;
    const aliases = {
      'eng': 'en', 'ben': 'bn', 'beng': 'bn', 'hin': 'hi', 'urd': 'ur',
      'ara': 'ar', 'spa': 'es', 'fre': 'fr', 'fra': 'fr',
      'ger': 'de', 'deu': 'de', 'por': 'pt', 'rus': 'ru',
      'jpn': 'ja', 'kor': 'ko', 'chi': 'zh', 'zho': 'zh',
      'tur': 'tr', 'ita': 'it', 'nld': 'nl', 'pol': 'pl',
      'tha': 'th', 'ind': 'id', 'msa': 'ms', 'fas': 'fa',
    };
    return aliases[language] ?? language;
  }

  static void _requireHttps(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Only public HTTPS extension URLs are allowed.');
    }
  }

  void dispose() => _client.close();
}
).hasMatch(normalizedImdbId)) return const [];
    final type = mediaType == 'tv' || mediaType == 'series' ? 'series' : 'movie';
    final requestedLanguages = languages.map(_normalizeLanguage)
        .where((value) => value.isNotEmpty).toSet();
    final extensions = await loadExtensions();
    final results = <FlixoraSubtitleExtensionResult>[];

    for (final extension in extensions) {
      if (extension.types.isNotEmpty && !extension.types.contains(type)) continue;
      if (extension.languages.isNotEmpty &&
          requestedLanguages.isNotEmpty &&
          !extension.languages.any(requestedLanguages.contains)) continue;
      try {
        final manifest = await _loadManifest(extension);
        if (!_supportsSubtitleResource(manifest, type)) continue;
        final id = type == 'series'
            ? 'tmdb:$tmdbId:$season:$episode'
            : 'tmdb:$tmdbId';
        final endpoint = _subtitleEndpoint(extension.manifestUrl, type, id);
        final response = await _client.get(
          endpoint,
          headers: const {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is! Map || payload['subtitles'] is! List) continue;
        for (final raw in payload['subtitles'] as List) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final subtitleUrl = Uri.tryParse((item['url'] ?? '').toString());
          if (subtitleUrl == null || subtitleUrl.scheme != 'https' ||
              subtitleUrl.host.isEmpty) continue;
          final language = _normalizeLanguage(item['lang']?.toString() ?? '');
          if (language.isEmpty ||
              (requestedLanguages.isNotEmpty &&
               !requestedLanguages.contains(language))) continue;
          results.add(FlixoraSubtitleExtensionResult(
            extensionId: extension.id,
            extensionName: extension.name,
            id: (item['id'] ?? '').toString(),
            url: subtitleUrl,
            language: language,
            label: (item['label'] ?? extension.name).toString(),
          ));
        }
      } catch (_) {
        // Fail over: a broken or unavailable add-on cannot block the next one.
        continue;
      }
    }
    return results;
  }

  Future<Map<String, dynamic>> _loadManifest(
    FlixoraSubtitleExtension extension,
  ) async {
    _requireHttps(extension.manifestUrl);
    final response = await _client.get(
      extension.manifestUrl,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Add-on manifest HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        (decoded['id'] ?? '').toString() != extension.id ||
        decoded['resources'] is! List) {
      throw const FormatException('Invalid Stremio subtitle add-on manifest.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  bool _supportsSubtitleResource(Map<String, dynamic> manifest, String type) {
    final resources = manifest['resources'] as List;
    final supportsSubtitles = resources.any((resource) =>
        resource == 'subtitles' ||
        (resource is Map && resource['name'] == 'subtitles'));
    if (!supportsSubtitles) return false;
    final rawTypes = manifest['types'];
    if (rawTypes is List && !rawTypes.contains(type)) return false;
    return true;
  }

  Uri _subtitleEndpoint(Uri manifestUrl, String type, String id) {
    final base = manifestUrl.resolve('.');
    return base.resolve(
      'subtitles/$type/${Uri.encodeComponent(id)}.json',
    );
  }

  static String _normalizeLanguage(String value) {
    final language = value.trim().toLowerCase().split(RegExp('[-_]')).first;
    const aliases = {
      'eng': 'en', 'ben': 'bn', 'hin': 'hi', 'urd': 'ur',
      'ara': 'ar', 'spa': 'es', 'fre': 'fr', 'fra': 'fr',
      'ger': 'de', 'deu': 'de', 'por': 'pt', 'rus': 'ru',
      'jpn': 'ja', 'kor': 'ko', 'chi': 'zh', 'zho': 'zh',
      'tur': 'tr', 'ita': 'it', 'nld': 'nl', 'pol': 'pl',
      'tha': 'th', 'ind': 'id', 'msa': 'ms', 'fas': 'fa',
    };
    return aliases[language] ?? language;
  }

  static void _requireHttps(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Only public HTTPS extension URLs are allowed.');
    }
  }

  void dispose() => _client.close();
}
