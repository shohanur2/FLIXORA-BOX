import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

class _ExtensionHttpFailure implements Exception {
  const _ExtensionHttpFailure(this.statusCode, {this.retryAfterSeconds = 0});
  final int statusCode;
  final int retryAfterSeconds;
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

  static const String _cooldownPrefix = 'flixora_subtitle_extension_cooldown_';

  Future<bool> _isCoolingDown(String extensionId) async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt('$_cooldownPrefix$extensionId') ?? 0;
    if (until <= DateTime.now().millisecondsSinceEpoch) {
      if (until != 0) await prefs.remove('$_cooldownPrefix$extensionId');
      return false;
    }
    return true;
  }

  static Future<void> markExtensionHttpFailure(
    String extensionId, {
    required int statusCode,
    int retryAfterSeconds = 0,
  }) async {
    final duration = statusCode == 429
        ? Duration(seconds: retryAfterSeconds.clamp(60, 21600).toInt())
        : (statusCode == 401 || statusCode == 403)
            ? const Duration(minutes: 30)
            : statusCode >= 500
                ? const Duration(minutes: 3)
                : Duration.zero;
    if (duration <= Duration.zero) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_cooldownPrefix$extensionId',
      DateTime.now().add(duration).millisecondsSinceEpoch,
    );
  }

  Future<void> _coolDown(String extensionId, Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setInt('$_cooldownPrefix$extensionId', until);
  }

  Duration _cooldownFor(_ExtensionHttpFailure failure) {
    if (failure.statusCode == 429) {
      final seconds = failure.retryAfterSeconds.clamp(60, 21600).toInt();
      return Duration(seconds: seconds);
    }
    if (failure.statusCode == 401 || failure.statusCode == 403) {
      return const Duration(minutes: 30);
    }
    if (failure.statusCode >= 500) return const Duration(minutes: 3);
    return Duration.zero;
  }

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

    // Query independent add-ons concurrently. Sequential manifest + subtitle
    // requests could consume the whole player timeout before later add-ons run.
    final batches = await Future.wait(extensions.map((extension) async {
      if (await _isCoolingDown(extension.id)) {
        return const <FlixoraSubtitleExtensionResult>[];
      }
      if (extension.types.isNotEmpty && !extension.types.contains(type)) {
        return const <FlixoraSubtitleExtensionResult>[];
      }
      if (extension.languages.isNotEmpty && requested.isNotEmpty &&
          !extension.languages.any(requested.contains)) {
        return const <FlixoraSubtitleExtensionResult>[];
      }
      try {
        final manifest = await _loadManifest(extension);
        if (!_supportsSubtitleResource(manifest, type, id)) {
          return const <FlixoraSubtitleExtensionResult>[];
        }

        final resourceId = type == 'series' ? '$id:$season:$episode' : id;
        final endpoint = _subtitleEndpoint(extension.manifestUrl, type, resourceId);
        final response = await _client.get(endpoint,
            headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          throw _ExtensionHttpFailure(
            response.statusCode,
            retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 0,
          );
        }
        final payload = jsonDecode(utf8.decode(response.bodyBytes));
        if (payload is! Map || payload['subtitles'] is! List) {
          return const <FlixoraSubtitleExtensionResult>[];
        }

        final results = <FlixoraSubtitleExtensionResult>[];
        for (final raw in payload['subtitles'] as List) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final subtitleUrl = Uri.tryParse((item['url'] ?? '').toString());
          if (subtitleUrl == null || subtitleUrl.scheme != 'https' ||
              subtitleUrl.host.isEmpty || subtitleUrl.userInfo.isNotEmpty) {
            continue;
          }
          final rawLanguage = (item['lang'] ?? '').toString();
          final languageParts = rawLanguage.split('+')
              .map(_normalizeLanguage).where((value) => value.isNotEmpty).toSet();
          final isDualLanguage = languageParts.length > 1 &&
              requested.isNotEmpty && requested.every(languageParts.contains);
          final language = isDualLanguage
              ? 'bn+en'
              : _normalizeLanguage(rawLanguage);
          if (language.isEmpty ||
              (!isDualLanguage && requested.isNotEmpty && !requested.contains(language))) {
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
        return results;
      } on _ExtensionHttpFailure catch (failure) {
        final cooldown = _cooldownFor(failure);
        if (cooldown > Duration.zero) {
          await _coolDown(extension.id, cooldown);
        }
        return const <FlixoraSubtitleExtensionResult>[];
      } on TimeoutException {
        await _coolDown(extension.id, const Duration(minutes: 2));
        return const <FlixoraSubtitleExtensionResult>[];
      } catch (_) {
        // One add-on's failure cannot block the other independent add-ons.
        return const <FlixoraSubtitleExtensionResult>[];
      }
    }));

    return batches.expand((batch) => batch).toList(growable: false);
  }

  Future<Map<String, dynamic>> _loadManifest(
      FlixoraSubtitleExtension extension) async {
    _requireHttps(extension.manifestUrl);
    final response = await _client.get(extension.manifestUrl,
        headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw _ExtensionHttpFailure(
        response.statusCode,
        retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? '') ?? 0,
      );
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
      'eng': 'en', 'english': 'en', 'ben': 'bn', 'beng': 'bn',
      'bengali': 'bn', 'bangla': 'bn', 'hin': 'hi', 'hindi': 'hi', 'urd': 'ur',
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
