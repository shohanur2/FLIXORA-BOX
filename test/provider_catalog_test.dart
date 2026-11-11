import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/provider_catalog.dart';

void main() {
  group('ProviderCatalog.forMovie', () {
    test('builds the nine existing providers plus VidRift for a TMDB movie', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );

      expect(sources, hasLength(10));
      expect(sources.map((source) => source.id).toList(), [
        'play4u',
        'yapgrid',
        'pvrplay',
        'cinesrc',
        'framex',
        'streamrip',
        'filmu',
        'multiembed',
        'nexstream',
        'vidrift-movie',
      ]);
      expect(sources.first.id, 'play4u');
      expect(sources.first.isAvailable, isTrue);
      expect(
        sources.first.url,
        'https://play4u.org/watch/tt0816692?embed=1',
      );
      expect(sources.first.loadInIframe, isFalse);
      expect(sources.first.unavailableReason, isNull);
      expect(
        sources[1].url,
        'https://yapgrid.com/embed/movie/157336?autoplay=1',
      );
      expect(sources[2].url, contains('/watch/movie/157336'));
      expect(sources[9].url,
          'https://embed.vidrift.net/embed/movie/157336?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1');
      expect(sources.first.isAvailable, isTrue);
      expect(sources.skip(1).every((source) => source.isAvailable), isTrue);
      expect(sources.last.loadInIframe, isTrue);
    });

    test('requires a valid IMDb ID for the Play4U movie route', () {
      final missing = ProviderCatalog.forMovie(tmdbId: 157336);
      final invalid = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: '157336',
      );

      expect(missing.first.isAvailable, isFalse);
      expect(missing.first.url, isEmpty);
      expect(missing.first.unavailableReason, contains('IMDb title ID'));
      expect(invalid.first.isAvailable, isFalse);
      expect(invalid.first.url, isEmpty);
      expect(missing[1].isAvailable, isTrue);
    });

    test('all configured provider URLs are HTTPS and match their approved hosts', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );

      for (final source in sources.where((item) => item.isAvailable)) {
        final uri = Uri.parse(source.url);
        expect(uri.scheme, 'https', reason: source.id);
        expect(
          ProviderCatalog.allowsNavigation(source, uri),
          isTrue,
          reason: source.id,
        );
      }
    });

    test('does not build providers without a TMDB ID', () {
      expect(ProviderCatalog.forMovie(tmdbId: 0), isEmpty);
    });

    test('creates a NexStream URL with a dynamic demo key', () {
      final source = ProviderCatalog.forMovie(tmdbId: 157336)
          .singleWhere((item) => item.id == 'nexstream');

      expect(
        source.url,
        matches(RegExp(
          r'^https://api\.codespecters\.com/embed/movie/157336\?apikey=DEMO_[0-9a-f]{8}$',
        )),
      );
    });
  });

  group('ProviderCatalog IMDb metadata', () {
    test('reads IMDb ID from appended external_ids', () {
      expect(
        ProviderCatalog.imdbIdFromTmdbDetails({
          'external_ids': {'imdb_id': 'tt0816692'},
        }),
        'tt0816692',
      );
    });

    test('falls back to the direct movie imdb_id field', () {
      expect(
        ProviderCatalog.imdbIdFromTmdbDetails({'imdb_id': 'tt0137523'}),
        'tt0137523',
      );
    });

    test('rejects malformed IMDb identifiers instead of guessing', () {
      expect(
        ProviderCatalog.imdbIdFromTmdbDetails({
          'external_ids': {'imdb_id': '157336'},
          'imdb_id': 'not-an-imdb-id',
        }),
        isNull,
      );
    });
  });

  group('ProviderCatalog TV and anime', () {
    test('builds ten TV provider candidates and requires an IMDb ID for Play4U', () {
      final sources = ProviderCatalog.forTv(tmdbId: 1399);

      expect(sources, hasLength(10));
      expect(sources.map((source) => source.id).toList(), [
        'play4u-tv',
        'yapgrid-tv',
        'pvrplay-tv',
        'cinesrc-tv',
        'framex-tv',
        'streamrip-tv',
        'filmu-tv',
        'multiembed-tv',
        'nexstream-tv',
        'vidrift-tv',
      ]);
      expect(sources.first.isAvailable, isFalse);
      expect(sources.first.unavailableReason, contains('IMDb title ID'));
      expect(sources.last.loadInIframe, isTrue);
      expect(
        sources.last.url,
        'https://embed.vidrift.net/embed/tv/1399/1/1?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1',
      );
      for (final source in sources.where((item) => item.isAvailable)) {
        final uri = Uri.parse(source.url);
        expect(uri.scheme, 'https', reason: source.id);
        expect(ProviderCatalog.allowsNavigation(source, uri), isTrue,
            reason: source.id);
      }
    });

    test('builds the Play4U embed route for the exact selected TV episode', () {
      final sources = ProviderCatalog.forTv(
        tmdbId: 1399,
        imdbId: 'tt0903747',
        seasonNumber: 2,
        episodeNumber: 5,
      );
      final play4u = sources.first;

      expect(play4u.id, 'play4u-tv');
      expect(play4u.isAvailable, isTrue);
      expect(
        play4u.url,
        'https://play4u.org/series/tt0903747/s-02/ep-05?cont=1',
      );
      expect(play4u.loadInIframe, isFalse);
      expect(play4u.unavailableReason, isNull);
    });

    test('matches the three Play4U sample routes supplied for FLIXORA', () {
      final movieSources = ProviderCatalog.forMovie(
        tmdbId: 34339725,
        imdbId: 'tt34339725',
      );
      final firstEpisodeSources = ProviderCatalog.forTv(
        tmdbId: 1,
        imdbId: 'tt36458668',
        seasonNumber: 1,
        episodeNumber: 1,
      );
      final seventhEpisodeSources = ProviderCatalog.forTv(
        tmdbId: 1,
        imdbId: 'tt23112594',
        seasonNumber: 1,
        episodeNumber: 7,
      );

      expect(movieSources.first.url,
          'https://play4u.org/watch/tt34339725?embed=1');
      expect(firstEpisodeSources.first.url,
          'https://play4u.org/series/tt36458668/s-01/ep-01?cont=1');
      expect(seventhEpisodeSources.first.url,
          'https://play4u.org/series/tt23112594/s-01/ep-07?cont=1');
      expect(movieSources.first.loadInIframe, isFalse);
      expect(firstEpisodeSources.first.loadInIframe, isFalse);
      expect(seventhEpisodeSources.first.loadInIframe, isFalse);
    });

    test('builds the exact selected TV season and episode route', () {
      final sources = ProviderCatalog.forTv(
        tmdbId: 1399,
        seasonNumber: 3,
        episodeNumber: 7,
      );

      expect(
        sources.firstWhere((source) => source.id == 'vidrift-tv').url,
        'https://embed.vidrift.net/embed/tv/1399/3/7?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1',
      );
    });

    test('labels anime source variants with their language mode', () {
      final sources = ProviderCatalog.forTv(
        tmdbId: 1429,
        aniListId: 16498,
      );

      expect(sources.firstWhere((source) => source.id == 'vidrift-anime-sub').languageLabel, 'Sub');
      expect(sources.firstWhere((source) => source.id == 'vidrift-anime-dub').languageLabel, 'Dub');
      expect(sources.firstWhere((source) => source.id == 'play4u-tv').languageLabel, isNull);
    });

    test('builds separate AniList Sub and Dub routes with TMDB fallback', () {
      final sources = ProviderCatalog.forTv(tmdbId: 1429, aniListId: 16498);

      expect(sources.map((source) => source.id).take(3), [
        'play4u-tv',
        'vidrift-anime-sub',
        'vidrift-anime-dub',
      ]);
      expect(sources[0].id, 'play4u-tv');
      expect(sources[1].url, contains('/embed/anilist/16498/1'));
      expect(sources[2].url, contains('&dub=1'));
      expect(sources.length, 12);
      expect(
        sources.firstWhere((source) => source.id == 'vidrift-tv').url,
        contains('/embed/tv/1429/1/1'),
      );
    });

    test('uses exact TMDB season and episode route for later anime seasons', () {
      final sources = ProviderCatalog.forTv(
        tmdbId: 1429,
        aniListId: 16498,
        seasonNumber: 2,
        episodeNumber: 4,
        aniListEpisodeNumber: 17,
      );

      expect(sources, hasLength(10));
      expect(
        sources.firstWhere((source) => source.id == 'vidrift-tv').url,
        contains('/embed/tv/1429/2/4?'),
      );
    });

    test('does not create TV providers without a TMDB ID', () {
      expect(ProviderCatalog.forTv(tmdbId: 0), isEmpty);
    });
  });

  group('ProviderCatalog fallback', () {
    test('tries the next available provider and skips already failed providers', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );
      final next = ProviderCatalog.nextAvailableAfter(
        sources,
        'play4u',
        excludedIds: const <String>{'yapgrid'},
      );

      expect(next?.id, 'pvrplay');
    });

    test('wraps to earlier providers after the last source fails', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );
      expect(
        ProviderCatalog.nextAvailableAfter(
          sources,
          'vidrift-movie',
          excludedIds: const <String>{'vidrift-movie'},
        )?.id,
        'play4u',
      );
    });
  });

  group('ProviderCatalog.allowsNavigation', () {
    final source = ProviderCatalog.forMovie(
      tmdbId: 157336,
      imdbId: 'tt0816692',
    )[0];

    test('allows HTTPS on the provider domain and its subdomains', () {
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://play4u.org/watch/tt0816692'),
        ),
        isTrue,
      );
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://cdn.play4u.org/video'),
        ),
        isTrue,
      );
    });

    test('allows the reference PVRPlay long subdomain', () {
      final pvr = ProviderCatalog.forMovie(tmdbId: 157336)[2];
      final uri = Uri.parse(pvr.url);

      expect(uri.host.endsWith('.pvrplay.fun'), isTrue);
      expect(ProviderCatalog.allowsNavigation(pvr, uri), isTrue);
    });

    test('allows Play4U secure nested player hosts without allowing local targets', () {
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('https://play4u.org/player/frame'),
        ),
        isTrue,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('https://unknown-player.example/embed'),
        ),
        isTrue,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('https://192.168.1.10/player/frame'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('https://127.0.0.1/player/frame'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('https://localhost/player/frame'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('http://play4u.org/player/frame'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          source,
          Uri.parse('https://user:pass@unknown-player.example/embed'),
        ),
        isFalse,
      );
    });

    test('keeps non-Play4U provider subframes on the strict host allowlist', () {
      final yapgrid = ProviderCatalog.forMovie(tmdbId: 157336)[1];
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          yapgrid,
          Uri.parse('https://yapgrid.com/player/frame'),
        ),
        isTrue,
      );
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          yapgrid,
          Uri.parse('https://unknown-player.example/embed'),
        ),
        isFalse,
      );
    });

    test('allows secure nested hosts for Play4U TV episodes', () {
      final play4uTv = ProviderCatalog.forTv(
        tmdbId: 1399,
        imdbId: 'tt0903747',
      ).first;
      expect(
        ProviderCatalog.allowsSubframeNavigation(
          play4uTv,
          Uri.parse('https://video-cdn.example/player'),
        ),
        isTrue,
      );
    });

    test('blocks HTTP, credentials, and unrelated domains', () {
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('http://play4u.org/watch/tt0816692'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://play4u.org.evil.example/watch'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://user:pass@play4u.org/watch'),
        ),
        isFalse,
      );
    });
  });

  group('ProviderCatalog.fromAdminUrl', () {
    test('converts YouTube watch and short links to in-app embeds', () {
      final watch = ProviderCatalog.fromAdminUrl(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      final short = ProviderCatalog.fromAdminUrl(
        'https://youtu.be/dQw4w9WgXcQ',
      );

      expect(watch?.id, 'youtube');
      expect(watch?.url, contains('youtube-nocookie.com/embed/dQw4w9WgXcQ'));
      expect(short?.url, watch?.url);
    });

    test('converts Vimeo links to the Vimeo player', () {
      final source = ProviderCatalog.fromAdminUrl(
        'https://vimeo.com/123456789',
      );

      expect(source?.id, 'vimeo');
      expect(source?.url, 'https://player.vimeo.com/video/123456789');
    });

    test('converts Internet Archive detail links to the embed player', () {
      final source = ProviderCatalog.fromAdminUrl(
        'https://archive.org/details/feature_film',
      );

      expect(source?.id, 'internet-archive');
      expect(source?.url, 'https://archive.org/embed/feature_film');
    });

    test('does not pretend Dailymotion is available without a Player ID', () {
      final source = ProviderCatalog.fromAdminUrl(
        'https://www.dailymotion.com/video/x84sh87',
      );

      expect(source?.id, 'dailymotion');
      expect(source?.isAvailable, isFalse);
      expect(source?.unavailableReason, contains('Player ID'));
    });

    test('keeps Admin embed sources available without a TMDB ID', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 0,
        adminVideoUrl: 'https://youtu.be/dQw4w9WgXcQ',
      );

      expect(sources, hasLength(1));
      expect(sources.single.id, 'youtube');
      expect(sources.single.isAvailable, isTrue);
    });

    test('rejects unrelated, malformed and unsafe embed URLs', () {
      expect(
        ProviderCatalog.fromAdminUrl('https://example.com/video/123456'),
        isNull,
      );
      expect(
        ProviderCatalog.fromAdminUrl('javascript:alert(1)'),
        isNull,
      );
      expect(
        ProviderCatalog.fromAdminUrl(
          'https://user:pass@www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        isNull,
      );
    });
  });
}
