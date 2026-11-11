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
    this.loadInIframe = false,
    this.languageLabel,
    this.isDirectMedia = false,
    this.httpHeaders = const <String, String>{},
  });

  final String id;
  final String name;
  final String url;
  final Set<String> allowedHosts;
  final String? unavailableReason;
  final bool loadInIframe;

  /// Optional language/track label for sources with a known variant, e.g.
  /// Anime Sub or Dub. Null means the provider controls language selection.
  final String? languageLabel;

  /// True when [url] is a direct media resource for media_kit/Media3.
  final bool isDirectMedia;

  /// Optional HTTP headers required by a provider's public media endpoint.
  final Map<String, String> httpHeaders;

  bool get isAvailable => url.isNotEmpty;
}

class ProviderCatalog {
  ProviderCatalog._();

  /// Configure this through the DAILYMOTION_PLAYER_ID GitHub Actions secret.
  static const String _dailymotionPlayerId =
      String.fromEnvironment('DAILYMOTION_PLAYER_ID');

  /// Reads a real IMDb title ID from TMDB detail payloads. Movie details
  /// may expose imdb_id directly, while appended/external_ids responses use
  /// external_ids.imdb_id. Never substitute a numeric TMDB ID.
  static String? imdbIdFromTmdbDetails(Map<String, dynamic> details) {
    final externalIds = details['external_ids'];
    final candidates = <dynamic>[
      if (externalIds is Map) externalIds['imdb_id'],
      details['imdb_id'],
    ];
    for (final candidate in candidates) {
      final id = (candidate ?? '').toString().trim();
      if (RegExp(r'^tt\d+$', caseSensitive: false).hasMatch(id)) {
        return id;
      }
    }
    return null;
  }

  /// Play4U routes require a valid IMDb title ID, never a numeric TMDB ID.
  static String? _validatedPlay4uImdbId(String? rawId) {
    final id = (rawId ?? '').trim();
    return RegExp(r'^tt\d+$', caseSensitive: false).hasMatch(id)
        ? id
        : null;
  }

  /// Reference movie embed route: /watch/{IMDb_ID}?embed=1
  static String _play4uMovieUrl(String? imdbId) {
    final id = _validatedPlay4uImdbId(imdbId);
    return id == null ? '' : 'https://play4u.org/watch/$id?embed=1';
  }

  /// Reference TV embed route: /series/{IMDb_ID}/s-XX/ep-XX?cont=1
  static String _play4uTvUrl(String? imdbId, int season, int episode) {
    final id = _validatedPlay4uImdbId(imdbId);
    if (id == null) return '';
    final safeSeason = season > 0 ? season : 1;
    final safeEpisode = episode > 0 ? episode : 1;
    final seasonPart = safeSeason.toString().padLeft(2, '0');
    final episodePart = safeEpisode.toString().padLeft(2, '0');
    return 'https://play4u.org/series/$id/s-$seasonPart/ep-$episodePart?cont=1';
  }

  // Redirect destinations approved by FLIXORA-REFERENCE's playback security
  // registry. Main-frame redirects stay on this explicit HTTPS allowlist.
  static const Set<String> _approvedRedirectHosts = <String>{
    'play4u.org',
    'youtube.com',
    'youtube-nocookie.com',
    'youtu.be',
    'vimeo.com',
    'archive.org',
    'embed.vidrift.net',
    'embed.vidrift.in',
    'geo.dailymotion.com',
    'dailymotion.com',
    'dai.ly',
  };

  /// Converts an Admin-provided Dailymotion URL into the current Player-ID
  /// based embed URL. Dailymotion requires a valid Player ID for playback.
  static ProviderEmbedSource? fromDailymotionUrl(
    String rawUrl, {
    String? playerId,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final isDailymotionHost = host == 'dai.ly' ||
        host == 'dailymotion.com' ||
        host.endsWith('.dailymotion.com');
    if (!isDailymotionHost) return null;

    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    String? videoId;
    String? playlistId;
    String? embeddedPlayerId;

    if (host == 'dai.ly') {
      if (segments.isNotEmpty) videoId = segments.first;
    } else if (segments.length >= 3 &&
        segments[0] == 'embed' &&
        segments[1] == 'video') {
      videoId = segments[2];
    } else if (segments.length >= 2 && segments[0] == 'video') {
      videoId = segments[1];
    } else if (segments.length >= 3 &&
        segments[0] == 'embed' &&
        segments[1] == 'playlist') {
      playlistId = segments[2];
    } else if (segments.length >= 2 && segments[0] == 'playlist') {
      playlistId = segments[1];
    } else if (segments.length >= 2 && segments[0] == 'player') {
      final playerSegment = segments[1];
      embeddedPlayerId = playerSegment.endsWith('.html')
          ? playerSegment.substring(0, playerSegment.length - 5)
          : playerSegment;
      videoId = uri.queryParameters['video'];
      playlistId = uri.queryParameters['playlist'];
    }

    final validContentId = RegExp(r'^[A-Za-z0-9]{3,64}$');
    if ((videoId == null || !validContentId.hasMatch(videoId)) &&
        (playlistId == null || !validContentId.hasMatch(playlistId))) {
      return null;
    }

    final configuredPlayerId = (playerId ?? _dailymotionPlayerId).trim();
    final effectivePlayerId = configuredPlayerId.isNotEmpty
        ? configuredPlayerId
        : (embeddedPlayerId ?? '').trim();
    final hasPlayerId = RegExp(r'^[A-Za-z0-9]{3,64}$')
        .hasMatch(effectivePlayerId);
    final embedUrl = hasPlayerId
        ? Uri.https(
            'geo.dailymotion.com',
            '/player/$effectivePlayerId.html',
            videoId != null
                ? <String, String>{'video': videoId}
                : <String, String>{'playlist': playlistId!},
          ).toString()
        : '';

    return ProviderEmbedSource(
      id: 'dailymotion',
      name: 'Dailymotion',
      url: embedUrl,
      allowedHosts: const <String>{
        'geo.dailymotion.com',
        'dailymotion.com',
        'dai.ly',
      },
      unavailableReason: hasPlayerId
          ? null
          : 'A Dailymotion Player ID is required. Add DAILYMOTION_PLAYER_ID to GitHub Actions secrets.',
    );
  }

  /// Converts supported Admin video-page URLs into official embeddable players.
  /// Direct MP4/HLS links are intentionally left to media_kit.
  static ProviderEmbedSource? fromAdminUrl(
    String rawUrl, {
    String? dailymotionPlayerId,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();

    final dailymotion = fromDailymotionUrl(
      rawUrl,
      playerId: dailymotionPlayerId,
    );
    if (dailymotion != null) return dailymotion;

    final isYouTube = host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
    if (isYouTube) {
      String? videoId;
      if (host == 'youtu.be') {
        if (segments.isNotEmpty) videoId = segments.first;
      } else if (segments.isNotEmpty && segments.first == 'watch') {
        videoId = uri.queryParameters['v'];
      } else if (segments.length >= 2 &&
          const <String>{'embed', 'shorts', 'live', 'v'}.contains(segments.first)) {
        videoId = segments[1];
      }
      if (videoId != null &&
          RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(videoId)) {
        return ProviderEmbedSource(
          id: 'youtube',
          name: 'YouTube',
          url: Uri.https(
            'www.youtube-nocookie.com',
            '/embed/$videoId',
            const <String, String>{'playsinline': '1'},
          ).toString(),
          allowedHosts: const <String>{
            'youtube.com',
            'youtube-nocookie.com',
            'youtu.be',
          },
        );
      }
      return null;
    }

    final isVimeo = host == 'vimeo.com' ||
        host.endsWith('.vimeo.com');
    if (isVimeo) {
      final videoId = segments.reversed
          .firstWhere(
            (part) => RegExp(r'^\d{5,12}$').hasMatch(part),
            orElse: () => '',
          );
      if (videoId.isNotEmpty) {
        return ProviderEmbedSource(
          id: 'vimeo',
          name: 'Vimeo',
          url: 'https://player.vimeo.com/video/$videoId',
          allowedHosts: const <String>{'vimeo.com'},
        );
      }
      return null;
    }

    final isArchive = host == 'archive.org' || host.endsWith('.archive.org');
    if (isArchive &&
        segments.length >= 2 &&
        const <String>{'details', 'embed'}.contains(segments.first)) {
      final identifier = segments[1];
      if (RegExp(r'^[A-Za-z0-9._-]{2,120}$').hasMatch(identifier)) {
        return ProviderEmbedSource(
          id: 'internet-archive',
          name: 'Internet Archive',
          url: 'https://archive.org/embed/${Uri.encodeComponent(identifier)}',
          allowedHosts: const <String>{'archive.org'},
        );
      }
    }

    return null;
  }

  /// Returns the built-in movie providers. Dailymotion is included only when
  /// the Admin source URL points to a Dailymotion video or playlist.
  /// Play4U uses the IMDb-based embed routes verified in FLIXORA-REFERENCE.
  static List<ProviderEmbedSource> forMovie({
    required int tmdbId,
    String? imdbId,
    String? dailymotionUrl,
    String? dailymotionPlayerId,
    String? adminVideoUrl,
  }) {
    final adminSource = fromAdminUrl(
      adminVideoUrl ?? dailymotionUrl ?? '',
      dailymotionPlayerId: dailymotionPlayerId,
    );
    if (tmdbId <= 0) {
      return adminSource == null
          ? const <ProviderEmbedSource>[]
          : <ProviderEmbedSource>[adminSource];
    }

    final id = tmdbId.toString();
    return <ProviderEmbedSource>[
      if (adminSource != null) adminSource,
      ProviderEmbedSource(
        id: 'play4u',
        name: 'STREAM 1 · Play4U',
        url: _play4uMovieUrl(imdbId),
        allowedHosts: const <String>{'play4u.org'},
        // Load Play4U directly so its own nested player frames remain in
        // control of playback instead of adding a second iframe wrapper.
        loadInIframe: false,
        unavailableReason: _validatedPlay4uImdbId(imdbId) == null
            ? 'Play4U requires a valid IMDb title ID (tt...). Choose another available stream for this title.'
            : null,
      ),
      ProviderEmbedSource(
        id: 'vidrift-movie',
        name: 'STREAM 2 · VidRift',
        url: 'https://embed.vidrift.net/embed/movie/$id?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1',
        allowedHosts: const <String>{
          'embed.vidrift.net',
          'embed.vidrift.in',
        },
        loadInIframe: true,
      ),
    ];
  }

  /// Builds the selected TMDB season/episode route. Anime Sub/Dub uses the
  /// absolute episode index expected by the AniList embed; the TMDB route stays
  /// available as a fallback for the exact selected season and episode.
  static List<ProviderEmbedSource> forTv({
    required int tmdbId,
    String? imdbId,
    int? aniListId,
    int seasonNumber = 1,
    int episodeNumber = 1,
    int? aniListEpisodeNumber,
    String? adminVideoUrl,
    String? dailymotionPlayerId,
  }) {
    final adminSource = fromAdminUrl(
      adminVideoUrl ?? '',
      dailymotionPlayerId: dailymotionPlayerId,
    );
    if (tmdbId <= 0) {
      return adminSource == null
          ? const <ProviderEmbedSource>[]
          : <ProviderEmbedSource>[adminSource];
    }

    final season = seasonNumber > 0 ? seasonNumber : 1;
    final episode = episodeNumber > 0 ? episodeNumber : 1;
    final animeEpisode = (aniListEpisodeNumber ?? episode) > 0
        ? (aniListEpisodeNumber ?? episode)
        : episode;
    const vidriftHosts = <String>{
      'embed.vidrift.net',
      'embed.vidrift.in',
    };
    const brand = '?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1';

    final play4u = ProviderEmbedSource(
      id: 'play4u-tv',
      name: 'STREAM 1 · Play4U',
      url: _play4uTvUrl(imdbId, season, episode),
      allowedHosts: const <String>{'play4u.org'},
      // Play4U owns its nested player frames; load its exact episode route.
      loadInIframe: false,
      unavailableReason: _validatedPlay4uImdbId(imdbId) == null
          ? 'Play4U requires a valid IMDb title ID for this series episode. Choose another available stream.'
          : null,
    );
    final vidriftTv = ProviderEmbedSource(
      id: 'vidrift-tv',
      name: 'STREAM 2 · VidRift',
      url: 'https://embed.vidrift.net/embed/tv/$tmdbId/$season/$episode$brand',
      allowedHosts: vidriftHosts,
      loadInIframe: true,
    );

    // Anime gets VidRift's AniList Sub/Dub routes as variants of the same
    // second provider. The TMDB TV route remains its final VidRift fallback.
    if (aniListId != null && aniListId > 0 && season == 1) {
      return <ProviderEmbedSource>[
        if (adminSource != null) adminSource,
        play4u,
        ProviderEmbedSource(
          id: 'vidrift-anime-sub',
          name: 'VidRift · Anime Sub',
          url: 'https://embed.vidrift.net/embed/anilist/$aniListId/$animeEpisode$brand',
          allowedHosts: vidriftHosts,
          loadInIframe: true,
          languageLabel: 'Sub',
        ),
        ProviderEmbedSource(
          id: 'vidrift-anime-dub',
          name: 'VidRift · Anime Dub',
          url: 'https://embed.vidrift.net/embed/anilist/$aniListId/$animeEpisode$brand&dub=1',
          allowedHosts: vidriftHosts,
          loadInIframe: true,
          languageLabel: 'Dub',
        ),
        vidriftTv,
      ];
    }

    return <ProviderEmbedSource>[
      if (adminSource != null) adminSource,
      play4u,
      vidriftTv,
    ];
  }

  /// Returns the next available provider after a failed source, wrapping once
  /// so the last preferred provider can still fall back to earlier sources.
  static ProviderEmbedSource? nextAvailableAfter(
    Iterable<ProviderEmbedSource> sources,
    String failedSourceId, {
    Set<String> excludedIds = const <String>{},
  }) {
    final items = sources.toList(growable: false);
    final failedIndex = items.indexWhere((item) => item.id == failedSourceId);
    if (failedIndex < 0) return null;

    for (var offset = 1; offset < items.length; offset++) {
      final index = (failedIndex + offset) % items.length;
      final candidate = items[index];
      if (candidate.isAvailable && !excludedIds.contains(candidate.id)) {
        return candidate;
      }
    }
    return null;
  }

  /// Play4U may host its player in a separate HTTPS frame; other providers
  /// remain restricted to their own and explicitly approved player hosts.
  /// Local/private targets and insecure schemes are always rejected.
  static bool allowsSubframeNavigation(
    ProviderEmbedSource source,
    Uri uri,
  ) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase();

    // The reference player embeds Play4U as a page, and that page owns its
    // nested video-player frames. Those frames can use separate HTTPS hosts.
    // Allow secure public hosts for Play4U only; keep local/private targets
    // and insecure schemes blocked, and retain strict allowlists elsewhere.
    if (source.id == 'play4u' ||
        source.id == 'play4u-tv' ||
        source.id.startsWith('vidrift-')) {
      return _isSafePublicHttpsSubframeHost(host);
    }

    final approvedHosts = <String>{
      ...source.allowedHosts,
      ..._approvedRedirectHosts,
    };
    return approvedHosts.any((allowed) {
      final domain = allowed.toLowerCase();
      return host == domain || host.endsWith('.$domain');
    });
  }

  static bool _isSafePublicHttpsSubframeHost(String host) {
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.contains(':') ||
        host == '0.0.0.0') {
      return false;
    }
    return !RegExp(
      r'^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[01])\.)',
    ).hasMatch(host);
  }

  /// Restricts main-frame navigation to the provider and approved redirects.
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
