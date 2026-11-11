import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'provider_catalog.dart';

/// Searches the federated PeerTube network through Sepia Search.
///
/// FLIXORA only accepts explicitly Public Domain / CC0 videos from public
/// instances. This avoids treating an unknown upload as an authorized source.
/// PeerTube is creator-hosted and is not a catalogue of every commercial film.
class PeerTubeSourceService {
  PeerTubeSourceService._();

  static const String _searchEndpoint =
      'https://sepiasearch.org/api/v1/search/videos';

  static final http.Client _client = http.Client();

  static Future<List<ProviderEmbedSource>> discover(
    String title, {
    String? year,
    required bool isTv,
    int season = 1,
    int episode = 1,
  }) async {
    final requestedTitle = title.trim();
    if (requestedTitle.isEmpty) return const <ProviderEmbedSource>[];

    final safeSeason = season > 0 ? season : 1;
    final safeEpisode = episode > 0 ? episode : 1;
    final query = isTv
        ? requestedTitle +
            ' S' +
            safeSeason.toString().padLeft(2, '0') +
            'E' +
            safeEpisode.toString().padLeft(2, '0')
        : requestedTitle;

    try {
      final uri = Uri.parse(_searchEndpoint).replace(
        queryParameters: <String, String>{
          'search': query,
          'count': '30',
          'nsfw': 'false',
          'isLive': 'false',
        },
      );
      final response = await _client
          .get(
            uri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'User-Agent': 'FLIXORA/1.0 (PeerTube public-domain search)',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return const <ProviderEmbedSource>[];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) {
        return const <ProviderEmbedSource>[];
      }

      final matches = <ProviderEmbedSource>[];
      final seen = <String>{};
      for (final raw in decoded['data'] as List) {
        if (raw is! Map) continue;
        final source = sourceFromVideo(
          Map<String, dynamic>.from(raw),
          requestedTitle: requestedTitle,
          requestedYear: year,
          isTv: isTv,
          season: safeSeason,
          episode: safeEpisode,
        );
        if (source == null || !seen.add(source.url)) continue;
        matches.add(source);
        if (matches.length >= 3) break;
      }
      return matches;
    } catch (_) {
      // PeerTube is optional; a search failure must never block FLIXORA.
      return const <ProviderEmbedSource>[];
    }
  }

  /// Public for deterministic unit tests and safe parsing of API results.
  static ProviderEmbedSource? sourceFromVideo(
    Map<String, dynamic> video, {
    required String requestedTitle,
    String? requestedYear,
    required bool isTv,
    int season = 1,
    int episode = 1,
  }) {
    if (!isPublicVideo(video)) return null;

    final name = (video['name'] ?? '').toString().trim();
    if (!matchesRequestedTitle(
      name,
      requestedTitle,
      requestedYear: requestedYear,
      isTv: isTv,
      season: season,
      episode: episode,
    )) {
      return null;
    }

    final uuid = (video['uuid'] ?? video['shortUUID'] ?? '').toString().trim();
    if (!isSafeVideoId(uuid)) return null;

    final host = _instanceHost(video);
    if (host == null) return null;

    final licence = licenceLabel(video['licence']);
    final embedUrl = Uri.https(
      host,
      '/videos/embed/' + Uri.encodeComponent(uuid),
      const <String, String>{
        'controls': '1',
        'controlBar': '1',
        'title': '1',
        'peertubeLink': '1',
        'p2p': '0',
      },
    ).toString();

    final isCc0 = licence.toLowerCase().contains('cc0');
    return ProviderEmbedSource(
      id: 'peertube-' + host.replaceAll('.', '-') + '-' + uuid,
      name: isCc0 ? 'PeerTube · CC0' : 'PeerTube · Public Domain',
      url: embedUrl,
      allowedHosts: <String>{host},
      // The URL is already PeerTube's official embed player; do not wrap it
      // in another iframe inside the FLIXORA WebView.
      loadInIframe: false,
    );
  }

  static bool isPublicVideo(Map<String, dynamic> video) {
    if (video['isLive'] == true || video['blacklisted'] == true) {
      return false;
    }

    final privacy = video['privacy'];
    if (privacy is! Map || _toInt(privacy['id']) != 1) {
      return false;
    }

    return isPublicDomainLicense(licenceLabel(video['licence']));
  }

  /// Only licences that explicitly waive copyright restrictions are accepted.
  /// Attribution, Non-Commercial, and No-Derivatives uploads are not auto-added.
  static bool isPublicDomainLicense(String label) {
    final value = label.trim().toLowerCase();
    return value.contains('public domain') || value.contains('cc0');
  }

  static String licenceLabel(dynamic value) {
    if (value is Map) {
      return (value['label'] ?? '').toString().trim();
    }
    return (value ?? '').toString().trim();
  }

  static bool matchesRequestedTitle(
    String candidate,
    String requested, {
    String? requestedYear,
    bool isTv = false,
    int season = 1,
    int episode = 1,
  }) {
    final candidateNormalized = _normalize(candidate);
    final requestedNormalized = _normalize(requested);
    if (candidateNormalized.isEmpty || requestedNormalized.isEmpty) {
      return false;
    }

    if (isTv) {
      if (!candidateNormalized.contains(requestedNormalized)) return false;
      final safeSeason = season > 0 ? season : 1;
      final safeEpisode = episode > 0 ? episode : 1;
      final seasonText = safeSeason.toString();
      final episodeText = safeEpisode.toString();
      final shortPattern = RegExp(
        r'\bs0*' +
            seasonText +
            r'[\s._-]*(?:e|ep)0*' +
            episodeText +
            r'\b',
        caseSensitive: false,
      );
      final longPattern = RegExp(
        r'\bseason\s+' +
            seasonText +
            r'[\s,._-]*(?:episode|ep)\s+0*' +
            episodeText +
            r'\b',
        caseSensitive: false,
      );
      return shortPattern.hasMatch(candidate) ||
          longPattern.hasMatch(candidate);
    }

    const allowedSuffixes = <String>[
      'full movie',
      'full film',
      'feature film',
      'public domain',
    ];
    final titleMatches = candidateNormalized == requestedNormalized ||
        allowedSuffixes.any((suffix) =>
            candidateNormalized == requestedNormalized + ' ' + suffix ||
            candidateNormalized.startsWith(
              requestedNormalized + ' ' + suffix + ' ',
            ));
    if (!titleMatches) return false;

    final requestedYearValue = (requestedYear ?? '').trim();
    final candidateYear = _yearInTitle(candidate);
    return candidateYear.isEmpty ||
        requestedYearValue.isEmpty ||
        candidateYear == requestedYearValue;
  }

  static bool isSafeVideoId(String value) {
    return value.length >= 8 &&
        value.length <= 80 &&
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
  }

  static bool isSafePublicHost(String value) {
    final host = value.trim().toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.contains(':') ||
        host.startsWith('.') ||
        host.endsWith('.')) {
      return false;
    }
    if (InternetAddress.tryParse(host) != null) return false;
    return RegExp(r'^[a-z0-9.-]+$').hasMatch(host) && host.contains('.');
  }

  static String? _instanceHost(Map<String, dynamic> video) {
    final rawUrl = (video['url'] ?? '').toString().trim();
    final videoUri = Uri.tryParse(rawUrl);
    if (videoUri != null &&
        videoUri.scheme == 'https' &&
        isSafePublicHost(videoUri.host)) {
      return videoUri.host.toLowerCase();
    }

    for (final key in <String>['account', 'channel']) {
      final value = video[key];
      if (value is! Map) continue;
      final rawHost = (value['host'] ?? '').toString().trim();
      if (isSafePublicHost(rawHost)) return rawHost.toLowerCase();

      final accountUrl = Uri.tryParse((value['url'] ?? '').toString());
      if (accountUrl != null &&
          accountUrl.scheme == 'https' &&
          isSafePublicHost(accountUrl.host)) {
        return accountUrl.host.toLowerCase();
      }
    }
    return null;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s._\-:;|,()\[\]{}!?]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _yearInTitle(String value) {
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(value);
    return match?.group(0) ?? '';
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
