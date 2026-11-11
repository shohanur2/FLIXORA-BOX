import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider_catalog.dart';

/// Finds films on Internet Archive only when item metadata explicitly declares
/// Public Domain/CC0 rights and includes a public browser-playable video file.
/// This is not a general-purpose movie mirror.
class PublicDomainMovieSourceService {
  PublicDomainMovieSourceService._();

  static final http.Client _client = http.Client();

  static Future<List<ProviderEmbedSource>> discover(
    String title, {
    String? year,
    required bool isTv,
  }) async {
    final requestedTitle = title.trim();
    if (isTv || requestedTitle.isEmpty) {
      return const <ProviderEmbedSource>[];
    }

    try {
      final query = 'mediatype:movies AND title:"' +
          requestedTitle.replaceAll('"', ' ') +
          '"';
      final searchUri = Uri.parse(
        'https://archive.org/advancedsearch.php?' +
            <String>[
              'q=' + Uri.encodeQueryComponent(query),
              'fl%5B%5D=identifier',
              'fl%5B%5D=title',
              'fl%5B%5D=year',
              'rows=8',
              'page=1',
              'output=json',
            ].join('&'),
      );

      final searchResponse = await _client
          .get(searchUri, headers: const <String, String>{
            'User-Agent': 'FLIXORA/1.0 (public-domain catalogue)',
          })
          .timeout(const Duration(seconds: 8));
      if (searchResponse.statusCode != 200) return const [];

      final searchJson = jsonDecode(searchResponse.body);
      if (searchJson is! Map) return const [];
      final response = searchJson['response'];
      if (response is! Map || response['docs'] is! List) return const [];

      final docs = (response['docs'] as List).whereType<Map>().where((item) {
        final candidateTitle = _text(item['title']);
        if (_normalize(candidateTitle) != _normalize(requestedTitle)) {
          return false;
        }
        final candidateYear = _year(item['year']);
        final requestedYear = (year ?? '').trim();
        return candidateYear.isEmpty ||
            requestedYear.isEmpty ||
            candidateYear == requestedYear;
      }).take(6).toList(growable: false);

      final results = await Future.wait<ProviderEmbedSource?>(
        docs.map((item) => _verifyItem(item)),
      );
      return results
          .whereType<ProviderEmbedSource>()
          .take(3)
          .toList(growable: false);
    } catch (_) {
      // Internet Archive is optional and must never block normal playback.
      return const <ProviderEmbedSource>[];
    }
  }

  static Future<ProviderEmbedSource?> _verifyItem(Map item) async {
    final identifier = _text(item['identifier']).trim();
    if (!isSafeIdentifier(identifier)) return null;

    try {
      final metadataUri = Uri.https('archive.org', '/metadata/' + identifier);
      final metadataResponse = await _client
          .get(metadataUri, headers: const <String, String>{
            'User-Agent': 'FLIXORA/1.0 (public-domain catalogue)',
          })
          .timeout(const Duration(seconds: 8));
      if (metadataResponse.statusCode != 200) return null;

      final itemJson = jsonDecode(metadataResponse.body);
      if (itemJson is! Map || itemJson['metadata'] is! Map) return null;
      final metadata = Map<dynamic, dynamic>.from(itemJson['metadata'] as Map);

      if (_text(metadata['mediatype']).toLowerCase() != 'movies' ||
          !isPublicDomainOrCc0(metadata) ||
          !hasSupportedVideoFile(itemJson['files'])) {
        return null;
      }

      final title = _text(metadata['title']);
      if (_normalize(title) != _normalize(_text(item['title']))) return null;

      final rightsText = (_text(metadata['licenseurl']) + ' ' +
              _text(metadata['rights']))
          .toLowerCase();
      final isCc0 = rightsText.contains('publicdomain/zero/1.0') ||
          rightsText.contains('cc0');

      return ProviderEmbedSource(
        id: 'internet-archive-' + identifier,
        name: isCc0
            ? 'Internet Archive · CC0'
            : 'Internet Archive · Public Domain',
        url: Uri.https('archive.org', '/embed/' + identifier).toString(),
        allowedHosts: const <String>{'archive.org'},
        loadInIframe: true,
        languageLabel: _text(metadata['language']).isEmpty
            ? null
            : _text(metadata['language']),
      );
    } catch (_) {
      return null;
    }
  }

  static String _text(dynamic value) {
    if (value is List) {
      return value.map((item) => item?.toString() ?? '').join(' ');
    }
    return (value ?? '').toString();
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _year(dynamic value) {
    final match = RegExp(r'(19|20)[0-9]{2}').firstMatch(_text(value));
    return match?.group(0) ?? '';
  }

  static bool isSafeIdentifier(String identifier) {
    return identifier.length >= 2 &&
        identifier.length <= 80 &&
        !RegExp(r'[^A-Za-z0-9_-]').hasMatch(identifier);
  }

  /// Accepts only explicit Public Domain Mark, CC0, or a rights statement
  /// that clearly declares the item to be in the public domain.
  static bool isPublicDomainOrCc0(Map<dynamic, dynamic> metadata) {
    final license = _text(metadata['licenseurl']).toLowerCase();
    final rights = _text(metadata['rights'])
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .toLowerCase();
    final restrictiveRights = rights.contains('not public domain') ||
        rights.contains('all rights reserved') ||
        rights.contains('copyright') ||
        rights.contains('permission required');
    if (restrictiveRights) return false;
    return license.contains('publicdomain/mark/1.0') ||
        license.contains('publicdomain/zero/1.0') ||
        license.contains('cc0') ||
        rights.contains('public domain') ||
        rights.contains('cc0');
  }

  /// Private files and non-video archives are never presented as playable.
  static bool hasSupportedVideoFile(dynamic rawFiles) {
    if (rawFiles is! List) return false;
    const extensions = <String>['.mp4', '.m4v', '.ogv', '.webm'];
    return rawFiles.whereType<Map>().any((file) {
      final name = _text(file['name']).toLowerCase();
      final isPrivate = _text(file['private']).toLowerCase() == 'true';
      return !isPrivate && extensions.any(name.endsWith);
    });
  }
}
