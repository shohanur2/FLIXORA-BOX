import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'provider_catalog.dart';

/// Discovers authorized direct media sources from configured external providers.
/// Admin-managed FLIXORA sources remain higher priority.
class AuthorizedProviderService {
  AuthorizedProviderService._();

  static final http.Client _client = http.Client();
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';

  static const String _fourKBaseUrl = String.fromEnvironment(
    'FLIXORA_4KHDHUB_BASE_URL',
    defaultValue: 'https://4khdhub.one/',
  );
  static const String _dramachiApiBaseUrl = String.fromEnvironment(
    'FLIXORA_DRAMACHI_API_BASE_URL',
    defaultValue: 'https://api.nodeobjects.com/',
  );
  static const String _circleFtpApiBaseUrl = String.fromEnvironment(
    'FLIXORA_CIRCLEFTP_API_BASE_URL',
    defaultValue: 'http://new.circleftp.net:5000/api',
  );

  static Future<List<ProviderEmbedSource>> discover({
    required String title,
    String? year,
    required bool isTv,
    int season = 1,
    int episode = 1,
  }) async {
    final query = title.trim();
    if (query.isEmpty) return const <ProviderEmbedSource>[];

    final results = await Future.wait<List<ProviderEmbedSource>>([
      _safe(() => _discoverDramachi(
            query,
            year: year,
            isTv: isTv,
            season: season,
            episode: episode,
          )),
      _safe(() => _discoverCircleFtp(
            query,
            year: year,
            isTv: isTv,
            season: season,
            episode: episode,
          )),
      _safe(() => _discoverFourKhdHub(
            query,
            year: year,
            isTv: isTv,
            season: season,
            episode: episode,
          )),
    ]);

    final seen = <String>{};
    return results
        .expand((items) => items)
        .where((source) => source.isAvailable && seen.add(source.url))
        .toList(growable: false);
  }

  static Future<List<ProviderEmbedSource>> _safe(
    Future<List<ProviderEmbedSource>> Function() task,
  ) async {
    try {
      return await task().timeout(const Duration(seconds: 12));
    } catch (_) {
      return const <ProviderEmbedSource>[];
    }
  }

  static Future<http.Response> _get(
    Uri uri, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const FormatException('Unsafe provider URL');
    }
    final response = await _client.get(
      uri,
      headers: const <String, String>{'User-Agent': _userAgent},
    ).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Provider returned HTTP ' + response.statusCode.toString());
    }
    return response;
  }

  static String _normalizeTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\(\s*\d{4}\s*\)'), ' ')
        .replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|4k|uhd|hdr|webrip|web-dl|bluray)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _matchesTitle(
    String candidate,
    String requested, {
    String? candidateYear,
    String? requestedYear,
  }) {
    final left = _normalizeTitle(candidate);
    final right = _normalizeTitle(requested);
    if (left.isEmpty || right.isEmpty) return false;
    final titleMatches = left == right ||
        (left.length >= 8 && right.length >= 8 &&
            (left.contains(right) || right.contains(left)));
    if (!titleMatches) return false;
    final a = (candidateYear ?? '').trim();
    final b = (requestedYear ?? '').trim();
    return a.isEmpty || b.isEmpty || a == b;
  }

  static String _yearFrom(dynamic value) {
    final raw = (value ?? '').toString();
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(raw);
    return match?.group(0) ?? '';
  }

  static bool _isSupportedMediaUrl(Uri uri) {
    if (uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return false;
    }
    final path = Uri.decodeComponent(uri.path).toLowerCase();
    return RegExp(r'\.(mp4|m4v|mkv|webm|mov|avi|m3u8|mpd)(?:$|/)').hasMatch(path);
  }

  static bool _isPublicHttpsUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return false;
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) return true;
    if (address.type != InternetAddressType.IPv4) return false;
    final octets = address.rawAddress;
    final first = octets[0];
    final second = octets[1];
    return first != 0 &&
        first != 10 &&
        first != 127 &&
        first < 224 &&
        !(first == 169 && second == 254) &&
        !(first == 172 && second >= 16 && second <= 31) &&
        !(first == 192 && second == 168);
  }

  static Uri? _normalizePixeldrainUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.contains('pixeldrain.')) return null;
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    String? id;
    if (segments.length >= 2 && segments[0] == 'u') {
      id = segments[1];
    } else if (segments.length >= 3 &&
        segments[0] == 'api' &&
        segments[1] == 'file') {
      id = segments[2];
    }
    if (id == null ||
        !RegExp(r'^[A-Za-z0-9_-]{2,128}$').hasMatch(id)) {
      return null;
    }
    return Uri.https(host, '/api/file/$id', <String, String>{'download': ''});
  }

  static Uri? _unwrapWatchOnlineUri(Uri uri) {
    if (!uri.host.toLowerCase().endsWith('pages.dev')) return null;
    final encoded = uri.queryParameters['u'];
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64.decode(encoded.replaceAll(' ', '+')));
      final target = Uri.tryParse(decoded);
      if (target != null && _isPublicHttpsUri(target)) return target;
    } catch (_) {}
    return null;
  }

  static bool _isApprovedResolverMedia(Uri uri) {
    if (!_isPublicHttpsUri(uri)) return false;
    if (_isSupportedMediaUrl(uri)) return true;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return (host.contains('pixeldrain.') && path.startsWith('/api/file/')) ||
        host == 'storage.googleapis.com' ||
        host.endsWith('.googleusercontent.com') ||
        host.endsWith('.googlevideo.com') ||
        host.endsWith('.workers.dev') ||
        host.endsWith('.r2.dev') ||
        host.endsWith('.cloudflarestorage.com');
  }

  static Future<List<Uri>> _resolveHubCloud(Uri resolverUri) async {
    final host = resolverUri.host.toLowerCase();
    final isHubCloud = host.contains('hubcloud.') &&
        resolverUri.path.startsWith('/drive/');
    final isHubDrive = host.contains('hubdrive.') &&
        resolverUri.path.startsWith('/file/');
    if (!_isPublicHttpsUri(resolverUri) || (!isHubCloud && !isHubDrive)) {
      return const <Uri>[];
    }

    var hubCloudUri = resolverUri;
    if (isHubDrive) {
      final driveHtml = (await _get(resolverUri)).body;
      final driveDoc = html_parser.parse(driveHtml);
      Uri? foundHubCloud;
      for (final anchor in driveDoc.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'];
        if (href == null) continue;
        final candidate = resolverUri.resolve(href);
        if (candidate.host.toLowerCase().contains('hubcloud.') &&
            candidate.path.startsWith('/drive/') &&
            _isPublicHttpsUri(candidate)) {
          foundHubCloud = candidate;
          break;
        }
      }
      if (foundHubCloud == null) return const <Uri>[];
      hubCloudUri = foundHubCloud;
    }

    final driveHtml = (await _get(hubCloudUri)).body;
    final driveDoc = html_parser.parse(driveHtml);
    Uri? nextResolver;
    for (final anchor in driveDoc.querySelectorAll(
      'a#download, a.btn-primary, a.btn-success, a.btn[href*="/download/"], a[href*="/download/"], a[href*="gamerxyt.com"], a[href*="hubcloud.php"]',
    )) {
      final href = anchor.attributes['href'];
      if (href == null || !href.startsWith('https://')) continue;
      final candidate = hubCloudUri.resolve(href);
      if (_isPublicHttpsUri(candidate)) {
        nextResolver = candidate;
        break;
      }
    }
    if (nextResolver == null) return const <Uri>[];

    final resolverHtml = (await _get(nextResolver)).body;
    final resolverDoc = html_parser.parse(resolverHtml);
    final candidates = <Uri>[];

    final pixelPattern = RegExp(
      r'https://pixeldrain\.(?:dev|com)/(?:u|api/file)/[A-Za-z0-9_-]+',
    );
    for (final match in pixelPattern.allMatches(resolverHtml)) {
      final parsed = Uri.tryParse(match.group(0) ?? '');
      if (parsed == null) continue;
      final normalized = _normalizePixeldrainUri(parsed);
      if (normalized != null) candidates.add(normalized);
    }

    for (final anchor in resolverDoc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null) continue;
      var candidate = Uri.tryParse(href);
      if (candidate == null) continue;
      if (!candidate.hasAuthority) candidate = nextResolver.resolve(href);

      final watchOnline = _unwrapWatchOnlineUri(candidate);
      if (watchOnline != null) candidate = watchOnline;
      final pixeldrain = _normalizePixeldrainUri(candidate);
      if (pixeldrain != null) candidate = pixeldrain;

      if (_isApprovedResolverMedia(candidate)) candidates.add(candidate);
    }

    final seen = <String>{};
    return candidates
        .where((uri) => seen.add(uri.toString()))
        .take(6)
        .toList(growable: false);
  }

  static ProviderEmbedSource _directSource({
    required String id,
    required String name,
    required Uri uri,
    String? language,
  }) {
    return ProviderEmbedSource(
      id: id,
      name: name,
      url: uri.toString(),
      allowedHosts: <String>{uri.host.toLowerCase()},
      isDirectMedia: true,
      languageLabel: language,
    );
  }

  // Dramachi's API returns catalogue metadata, episode IDs and CDN URLs in
  // normal JSON responses. No session, VIP or DRM bypass is used.
  static Future<List<ProviderEmbedSource>> _discoverDramachi(
    String title, {
    String? year,
    required bool isTv,
    required int season,
    required int episode,
  }) async {
    final searchUri = Uri.parse(_dramachiApiBaseUrl).replace(
      queryParameters: <String, String>{
        'interface': 'search',
        'q': title,
        'filter': 'all',
        'page': '1',
      },
    );
    final searchJson = jsonDecode((await _get(searchUri)).body);
    if (searchJson is! Map) return const <ProviderEmbedSource>[];
    final items = searchJson['data'];
    if (items is! List) return const <ProviderEmbedSource>[];

    Map? match;
    for (final item in items.whereType<Map>()) {
      final itemType = (item['content'] ?? '').toString().toLowerCase();
      final itemIsMovie = itemType == 'movie' || itemType == 'movies';
      if ((isTv != itemIsMovie) &&
          _matchesTitle(
            (item['title'] ?? '').toString(),
            title,
            candidateYear: _yearFrom(item['year']),
            requestedYear: year,
          )) {
        match = item;
        break;
      }
    }
    if (match == null) return const <ProviderEmbedSource>[];

    final titleId = (match['id'] ?? '').toString().trim();
    if (titleId.isEmpty) return const <ProviderEmbedSource>[];

    final detailsUri = Uri.parse(_dramachiApiBaseUrl).replace(
      queryParameters: <String, String>{
        'interface': 'title_v2',
        'id': titleId,
      },
    );
    final detailsJson = jsonDecode((await _get(detailsUri)).body);
    if (detailsJson is! Map) return const <ProviderEmbedSource>[];

    final seasons = detailsJson['seasons'];
    final versions = <Map>[];
    if (seasons is Map) {
      final entries = seasons.entries.toList()
        ..sort((a, b) => _seasonNumber(a.key.toString())
            .compareTo(_seasonNumber(b.key.toString())));
      if (isTv) {
        final target = entries.where(
          (entry) => _seasonNumber(entry.key.toString()) == season,
        );
        if (target.isNotEmpty && target.first.value is Map) {
          final list = (target.first.value as Map)['versions'];
          if (list is List) versions.addAll(list.whereType<Map>());
        }
      } else if (entries.isNotEmpty && entries.first.value is Map) {
        final list = (entries.first.value as Map)['versions'];
        if (list is List) versions.addAll(list.whereType<Map>());
      }
    }
    if (versions.isEmpty && !isTv) {
      versions.add(<String, dynamic>{'version_name': 'HD', 'rip': 'hd Rip'});
    }

    final output = <ProviderEmbedSource>[];
    for (final version in versions.take(4)) {
      final rip = (version['rip'] ?? '').toString().trim();
      if (rip.isEmpty) continue;

      final episodeListUri = Uri.parse(_dramachiApiBaseUrl).replace(
        queryParameters: <String, String>{
          'interface': 'eplist',
          'season': rip,
          'id': titleId,
        },
      );
      final episodeJson = jsonDecode((await _get(episodeListUri)).body);
      if (episodeJson is! Map || episodeJson['episode_list'] is! List) continue;
      final episodeItems =
          (episodeJson['episode_list'] as List).whereType<Map>().toList();
      if (episodeItems.isEmpty) continue;

      Map? selected;
      if (isTv) {
        selected = episodeItems.cast<Map?>().firstWhere(
          (item) => _episodeNumber((item?['f_title'] ?? '').toString()) == episode,
          orElse: () => null,
        );
        selected ??= episodeItems.length >= episode ? episodeItems[episode - 1] : null;
      } else {
        selected = episodeItems.first;
      }
      if (selected == null) continue;

      final fid = (selected['fid'] ?? '').toString().trim();
      final disk = (selected['disk'] ?? '').toString().trim();
      if (fid.isEmpty || disk.isEmpty) continue;

      final fileUri = Uri.parse(_dramachiApiBaseUrl).replace(
        queryParameters: <String, String>{
          'interface': 'getFile',
          'fid': fid,
          'findex': disk,
        },
      );
      final fileJson = jsonDecode((await _get(fileUri)).body);
      if (fileJson is! Map) continue;
      final hostInfo = fileJson['hostInfo'];
      final fileInfo = fileJson['fileInfo'];
      if (hostInfo is! Map || fileInfo is! List || fileInfo.isEmpty) continue;
      final host = (hostInfo['host'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
      final rawPath = ((fileInfo.first as Map)['url'] ?? '').toString().trim();
      if (host.isEmpty || rawPath.isEmpty) continue;

      final streamUri = Uri.tryParse(
        'https://' + host + '/cdn/' + rawPath.replaceFirst(RegExp(r'^/+'), ''),
      );
      if (streamUri == null ||
          streamUri.scheme != 'https' ||
          streamUri.host.isEmpty ||
          streamUri.userInfo.isNotEmpty) {
        continue;
      }

      final quality = (selected['quality'] ?? '').toString().trim();
      final versionName = (version['version_name'] ?? 'Dramachi').toString().trim();
      output.add(_directSource(
        id: 'dramachi-' + titleId + '-' + rip + '-' + fid,
        name: 'Dramachi · ' + versionName + (quality.isEmpty ? '' : ' · ' + quality),
        uri: streamUri,
        language: versionName,
      ));
    }
    return output;
  }

  static int _seasonNumber(String value) {
    final match = RegExp(r'(\d+)').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '') ?? 9999;
  }

  static int? _episodeNumber(String value) {
    final upper = value.toUpperCase();
    final match = RegExp(r'(?:S\d{1,2}\s*)?E(?:P)?\s*0*(\d+)').firstMatch(upper);
    if (match != null) return int.tryParse(match.group(1) ?? '');
    final last = RegExp(r'(\d+)\s*$').firstMatch(upper);
    return int.tryParse(last?.group(1) ?? '');
  }

  // CircleFTP is a BDIX catalogue API. It exposes direct file links in post
  // details; only the CircleFTP host is allowed over cleartext HTTP.
  static Future<List<ProviderEmbedSource>> _discoverCircleFtp(
    String title, {
    String? year,
    required bool isTv,
    required int season,
    required int episode,
  }) async {
    final rawBase = _circleFtpApiBaseUrl.endsWith('/')
        ? _circleFtpApiBaseUrl
        : _circleFtpApiBaseUrl + '/';
    final base = Uri.parse(rawBase);
    final searchUri = base.resolve('posts').replace(
      queryParameters: <String, String>{
        'searchTerm': title,
        'order': 'desc',
      },
    );
    final searchJson = jsonDecode((await _get(searchUri)).body);
    if (searchJson is! Map || searchJson['posts'] is! List) {
      return const <ProviderEmbedSource>[];
    }

    Map? match;
    for (final item in (searchJson['posts'] as List).whereType<Map>()) {
      final itemType = (item['type'] ?? '').toString().toLowerCase();
      final itemIsTv = itemType == 'series';
      if ((isTv == itemIsTv) &&
          _matchesTitle(
            (item['title'] ?? item['name'] ?? '').toString(),
            title,
            candidateYear: _yearFrom(item['year']),
            requestedYear: year,
          )) {
        match = item;
        break;
      }
    }
    if (match == null) return const <ProviderEmbedSource>[];

    final postId = (match['id'] ?? '').toString().trim();
    if (postId.isEmpty) return const <ProviderEmbedSource>[];
    final detailUri = base.resolve('posts/' + Uri.encodeComponent(postId));
    final detailJson = jsonDecode((await _get(detailUri)).body);
    if (detailJson is! Map) return const <ProviderEmbedSource>[];

    String link = '';
    if (isTv) {
      final content = detailJson['content'];
      if (content is List && season > 0 && episode > 0 &&
          content.length >= season && content[season - 1] is Map) {
        final episodes = (content[season - 1] as Map)['episodes'];
        if (episodes is List && episodes.length >= episode &&
            episodes[episode - 1] is Map) {
          link = ((episodes[episode - 1] as Map)['link'] ?? '').toString();
        }
      }
    } else {
      link = (detailJson['content'] ?? '').toString();
    }

    final uri = Uri.tryParse(link.trim());
    if (uri == null ||
        uri.host.toLowerCase() != 'new.circleftp.net' ||
        uri.userInfo.isNotEmpty ||
        uri.scheme != 'http' ||
        !_isSupportedMediaUrl(uri)) {
      return const <ProviderEmbedSource>[];
    }

    return <ProviderEmbedSource>[
      _directSource(
        id: 'circleftp-' + postId,
        name: 'BDIX · CircleFTP',
        uri: uri,
        language: _languageFromTitle((match['title'] ?? '').toString()),
      ),
    ];
  }

  // 4KHDHub pages are parsed for public, direct media links only. Resolver
  // pages and non-media redirects are not treated as playable sources.
  static Future<List<ProviderEmbedSource>> _discoverFourKhdHub(
    String title, {
    String? year,
    required bool isTv,
    required int season,
    required int episode,
  }) async {
    final base = Uri.parse(_fourKBaseUrl);
    if (base.scheme != 'https' || base.host.isEmpty) {
      return const <ProviderEmbedSource>[];
    }
    final searchUri = base.replace(
      queryParameters: <String, String>{'s': title},
    );
    final searchHtml = (await _get(searchUri)).body;
    final searchDoc = html_parser.parse(searchHtml);

    Uri? detailUri;
    for (final card in searchDoc.querySelectorAll('a.movie-card')) {
      final href = card.attributes['href'];
      final cardTitle =
          card.querySelector('.movie-card-title')?.text.trim() ?? '';
      final meta = card.querySelector('.movie-card-meta')?.text ?? '';
      final cardIsTv = href?.contains('-series-') ?? false;
      if (href == null ||
          cardIsTv != isTv ||
          !_matchesTitle(
            cardTitle,
            title,
            candidateYear: _yearFrom(meta),
            requestedYear: year,
          )) {
        continue;
      }
      final candidate = base.resolve(href);
      if (candidate.scheme == 'https' && candidate.host == base.host) {
        detailUri = candidate;
        break;
      }
    }
    if (detailUri == null) return const <ProviderEmbedSource>[];

    final detailHtml = (await _get(detailUri)).body;
    final detailDoc = html_parser.parse(detailHtml);
    final items = isTv
        ? detailDoc.querySelectorAll('#episodes .episode-download-item')
        : detailDoc.querySelectorAll('.download-item');
    final output = <ProviderEmbedSource>[];

    for (final item in items) {
      final filename = isTv
          ? item.querySelector('.episode-file-title')?.text.trim() ?? ''
          : item.querySelector('.file-title')?.text.trim() ?? '';
      if (filename.isEmpty) continue;
      if (isTv && _seasonEpisode(filename) != (season * 1000 + episode)) continue;

      for (final anchor in item.querySelectorAll('a[href]')) {
        final rawHref = anchor.attributes['href'];
        if (rawHref == null) continue;
        final uri = detailUri.resolve(rawHref);
        final host = uri.host.toLowerCase();
        if (host.contains('hubcloud.') || host.contains('hubdrive.')) {
          final resolved = await _resolveHubCloud(uri);
          for (var index = 0; index < resolved.length; index++) {
            final mediaUri = resolved[index];
            output.add(_directSource(
              id: '4khdhub-' + mediaUri.toString().hashCode.toString(),
              name: '4KHDHub · ' + filename + ' · Mirror ' + (index + 1).toString(),
              uri: mediaUri,
              language: _languageFromTitle(filename),
            ));
            if (output.length >= 4) return output;
          }
          continue;
        }
        if (!_isSupportedMediaUrl(uri) || !_isPublicHttpsUri(uri) ||
            host == base.host) {
          continue;
        }
        output.add(_directSource(
          id: '4khdhub-' + uri.toString().hashCode.toString(),
          name: '4KHDHub · ' + filename,
          uri: uri,
          language: _languageFromTitle(filename),
        ));
        if (output.length >= 4) return output;
      }
    }
    return output;
  }

  static int? _seasonEpisode(String value) {
    final match = RegExp(r'S(\d{1,2})\s*E(\d{1,3})', caseSensitive: false)
        .firstMatch(value);
    if (match == null) return null;
    final season = int.tryParse(match.group(1) ?? '');
    final episode = int.tryParse(match.group(2) ?? '');
    if (season == null || episode == null) return null;
    return season * 1000 + episode;
  }

  static String? _languageFromTitle(String value) {
    final lower = value.toLowerCase();
    const languages = <String, String>{
      'hindi': 'Hindi',
      'english': 'English',
      'bengali': 'Bengali',
      'bangla': 'Bengali',
      'tamil': 'Tamil',
      'telugu': 'Telugu',
      'korean': 'Korean',
      'japanese': 'Japanese',
      'chinese': 'Chinese',
      'dual audio': 'Dual Audio',
      'multi audio': 'Multi Audio',
    };
    for (final entry in languages.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
