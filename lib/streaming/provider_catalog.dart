/// Provider URL definitions ported from FLIXORA-REFERENCE.
///
/// Admin-managed direct MP4/HLS sources remain FLIXORA's first playback choice.
class ProviderEmbedSource {
  const ProviderEmbedSource({
    required this.id,
    required this.name,
    required this.url,
    required this.allowedHosts,
    this.unavailableReason,
  });

  final String id;
  final String name;
  final String url;
  final Set<String> allowedHosts;
  final String? unavailableReason;

  bool get isAvailable => url.isNotEmpty;
}

class ProviderCatalog {
  ProviderCatalog._();

  static const String _pvrPlayHost =
      'dbhnmkjasgbvsdkjbskkvnskjbfckldsnckjbckjnxkjcsknxjvkjxnvcxknvku.pvrplay.fun';

  // Redirect destinations approved by FLIXORA-REFERENCE's playback security
  // registry. Main-frame redirects stay on this explicit HTTPS allowlist.
  static const Set<String> _approvedRedirectHosts = <String>{
    'play4u.org',
    'yapgrid.com',
    'pvrplay.fun',
    'reelsdownload.online',
    'cinesrc.st',
    'framextv.xyz',
    'framextv.cc',
    'streamrip.fun',
    'filmu.in',
    'multiembed.mov',
    'codespecters.com',
    'youtube.com',
    'youtube-nocookie.com',
    'youtu.be',
    'vimeo.com',
    'archive.org',
  };

  /// Returns all nine built-in movie providers in reference-project order.
  /// Play4U requires the movie's real IMDb title ID; the others use TMDB ID.
  static List<ProviderEmbedSource> forMovie({
    required int tmdbId,
    String? imdbId,
  }) {
    if (tmdbId <= 0) return const <ProviderEmbedSource>[];

    final id = tmdbId.toString();
    final cleanImdbId = (imdbId ?? '').trim();
    final hasImdbId = RegExp(r'^tt\d+$', caseSensitive: false)
        .hasMatch(cleanImdbId);
    final nexStreamKey = _dynamicNexStreamDemoKey();

    return <ProviderEmbedSource>[
      ProviderEmbedSource(
        id: 'play4u',
        name: 'STREAM 1 · Play4U',
        url: hasImdbId
            ? 'https://play4u.org/watch/$cleanImdbId?embed=1'
            : '',
        allowedHosts: const <String>{'play4u.org'},
        unavailableReason:
            hasImdbId ? null : 'IMDb ID is not available for this movie.',
      ),
      ProviderEmbedSource(
        id: 'yapgrid',
        name: 'STREAM 2 · YapGrid',
        url: 'https://yapgrid.com/embed/movie/$id?autoplay=1',
        allowedHosts: const <String>{'yapgrid.com'},
      ),
      ProviderEmbedSource(
        id: 'pvrplay',
        name: 'STREAM 3 · PVRPlay',
        url: 'https://$_pvrPlayHost/watch/movie/$id',
        allowedHosts: const <String>{'pvrplay.fun'},
      ),
      ProviderEmbedSource(
        id: 'cinesrc',
        name: 'STREAM 4 · CineSRC',
        url: 'https://cinesrc.st/embed/movie/$id',
        allowedHosts: const <String>{'cinesrc.st'},
      ),
      ProviderEmbedSource(
        id: 'framex',
        name: 'STREAM 5 · Frame X',
        url: 'https://framextv.xyz/embed/$id',
        allowedHosts: const <String>{'framextv.xyz', 'framextv.cc'},
      ),
      ProviderEmbedSource(
        id: 'streamrip',
        name: 'STREAM 6 · Stream Rip',
        url: 'https://streamrip.fun/play?type=movie&id=$id',
        allowedHosts: const <String>{'streamrip.fun'},
      ),
      ProviderEmbedSource(
        id: 'filmu',
        name: 'STREAM 7 · FilmU',
        url: 'https://embed.filmu.in/movie/$id',
        allowedHosts: const <String>{'filmu.in'},
      ),
      ProviderEmbedSource(
        id: 'multiembed',
        name: 'STREAM 8 · Multiembed',
        url: 'https://multiembed.mov/?video_id=$id&tmdb=1',
        allowedHosts: const <String>{'multiembed.mov'},
      ),
      ProviderEmbedSource(
        id: 'nexstream',
        name: 'STREAM 9 · NexStream',
        url: 'https://api.codespecters.com/embed/movie/$id?apikey=$nexStreamKey',
        allowedHosts: const <String>{'codespecters.com'},
      ),
    ];
  }

  /// Mirrors the reference project's five-minute NexStream demo-key window.
  /// A provider-issued production API key can replace this if required.
  static String _dynamicNexStreamDemoKey() {
    final timeWindow =
        DateTime.now().millisecondsSinceEpoch ~/ 300000;
    final value = 'NEXSTREAM$timeWindow';
    var hash = 0;

    for (final unit in value.codeUnits) {
      hash = ((hash << 5) - hash + unit) & 0xffffffff;
    }

    if (hash >= 0x80000000) hash -= 0x100000000;
    final hex = hash.abs().toRadixString(16).padRight(8, '0');
    return 'DEMO_$hex';
  }

  /// Returns the next available provider after a failed source. The order is
  /// deterministic and never loops back to a provider that already failed.
  static ProviderEmbedSource? nextAvailableAfter(
    Iterable<ProviderEmbedSource> sources,
    String failedSourceId, {
    Set<String> excludedIds = const <String>{},
  }) {
    final items = sources.toList(growable: false);
    final failedIndex = items.indexWhere((item) => item.id == failedSourceId);
    if (failedIndex < 0) return null;

    for (var index = failedIndex + 1; index < items.length; index++) {
      final candidate = items[index];
      if (candidate.isAvailable && !excludedIds.contains(candidate.id)) {
        return candidate;
      }
    }
    return null;
  }

  /// Only HTTPS navigation on the provider's own domain (or its subdomains)
  /// is allowed inside the embedded player.
  static bool allowsNavigation(
    ProviderEmbedSource source,
    Uri uri,
  ) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase();
    final approvedHosts = <String>{
      ...source.allowedHosts,
      ..._approvedRedirectHosts,
    };
    return approvedHosts.any((allowed) {
      final domain = allowed.toLowerCase();
      return host == domain || host.endsWith('.$domain');
    });
  }
}
