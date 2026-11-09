import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/provider_catalog.dart';

void main() {
  group('ProviderCatalog.forMovie', () {
    test('builds all nine reference providers for a TMDB movie', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );

      expect(sources, hasLength(9));
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
      ]);
      expect(
        sources.first.url,
        'https://play4u.org/watch/tt0816692?embed=1',
      );
      expect(
        sources[1].url,
        'https://yapgrid.com/embed/movie/157336?autoplay=1',
      );
      expect(sources[2].url, contains('/watch/movie/157336'));
      expect(sources.every((source) => source.isAvailable), isTrue);
    });

    test('keeps Play4U visible but unavailable without a valid IMDb ID', () {
      final sources = ProviderCatalog.forMovie(tmdbId: 157336);

      expect(sources, hasLength(9));
      expect(sources.first.id, 'play4u');
      expect(sources.first.isAvailable, isFalse);
      expect(sources.first.unavailableReason, isNotNull);
      expect(sources[1].isAvailable, isTrue);
    });

    test('all configured provider URLs are HTTPS and match their approved hosts', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );

      for (final source in sources) {
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
      final source = ProviderCatalog.forMovie(tmdbId: 157336).last;

      expect(
        source.url,
        matches(RegExp(
          r'^https://api\.codespecters\.com/embed/movie/157336\?apikey=DEMO_[0-9a-f]{8}$',
        )),
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
}
