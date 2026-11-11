import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/authorized_provider_service.dart';
import 'package:flixora/streaming/public_domain_movie_source_service.dart';
import 'package:flixora/streaming/provider_catalog.dart';

void main() {
  group('AuthorizedProviderService', () {
    test('returns no results for a blank title without making requests', () async {
      final sources = await AuthorizedProviderService.discover(
        title: '   ',
        isTv: false,
      );

      expect(sources, isEmpty);
    });
  });

  group('PublicDomainMovieSourceService', () {
    test('accepts explicit Public Domain Mark and CC0 declarations', () {
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
        }),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'licenseurl': 'https://creativecommons.org/publicdomain/zero/1.0/',
        }),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'rights': 'This film is in the public domain.',
        }),
        isTrue,
      );
    });

    test('rejects missing or restrictive copyright declarations', () {
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'licenseurl': 'https://creativecommons.org/licenses/by-nc/4.0/',
          'rights': 'All rights reserved.',
        }),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0(const {}),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'rights': 'This work is not public domain. All rights reserved.',
        }),
        isFalse,
      );
    });

    test('only accepts safe Archive identifiers', () {
      expect(
        PublicDomainMovieSourceService.isSafeIdentifier('feature_film-1930'),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.isSafeIdentifier('../private'),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.isSafeIdentifier('x'),
        isFalse,
      );
    });

    test('requires a public video file and rejects private files', () {
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile([
          {'name': 'film.mp4'},
        ]),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile([
          {'name': 'film.mp4', 'private': 'true'},
        ]),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile([
          {'name': 'film.zip'},
          {'name': 'poster.jpg'},
        ]),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile(null),
        isFalse,
      );
    });

    test('does not search TV episodes or blank titles', () async {
      expect(
        await PublicDomainMovieSourceService.discover(
          '   ',
          isTv: false,
        ),
        isEmpty,
      );
      expect(
        await PublicDomainMovieSourceService.discover(
          'Example Series',
          isTv: true,
        ),
        isEmpty,
      );
    });
  });

  group('ProviderEmbedSource direct media', () {
    test('embed sources default to WebView mode', () {
      const source = ProviderEmbedSource(
        id: 'test-embed',
        name: 'Test Embed',
        url: 'https://example.com/embed/1',
        allowedHosts: <String>{'example.com'},
      );

      expect(source.isDirectMedia, isFalse);
      expect(source.isAvailable, isTrue);
    });

    test('direct media sources can opt into native playback', () {
      const source = ProviderEmbedSource(
        id: 'test-direct',
        name: 'Test Direct',
        url: 'https://cdn.example.com/movie.mp4',
        allowedHosts: <String>{'cdn.example.com'},
        isDirectMedia: true,
      );

      expect(source.isDirectMedia, isTrue);
      expect(source.isAvailable, isTrue);
      expect(source.httpHeaders, isEmpty);
    });
  });
}
