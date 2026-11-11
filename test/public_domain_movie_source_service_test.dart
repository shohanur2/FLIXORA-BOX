import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/public_domain_movie_source_service.dart';

void main() {
  group('Internet Archive rights verification', () {
    test('accepts explicit CC0 and Public Domain Mark licences', () {
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'licenseurl':
              'https://creativecommons.org/publicdomain/zero/1.0/',
          'rights': 'CC0 1.0 Universal',
        }),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'licenseurl':
              'https://creativecommons.org/publicdomain/mark/1.0/',
          'rights': 'Public Domain',
        }),
        isTrue,
      );
    });

    test('rejects attribution licences and restrictive rights statements', () {
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'licenseurl': 'https://creativecommons.org/licenses/by/4.0/',
          'rights': 'Public Domain',
        }),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'rights': 'All rights reserved. Copyright protected.',
        }),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'rights': 'Not in the public domain',
        }),
        isFalse,
      );
    });

    test('accepts clear public-domain rights text when no licence URL exists', () {
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'rights': 'This film is in the public domain.',
        }),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.isPublicDomainOrCc0({
          'rights': 'Uploaded by a user',
        }),
        isFalse,
      );
    });
  });

  group('Internet Archive video files and identifiers', () {
    test('requires a public supported video file', () {
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile([
          {'name': 'feature.mp4', 'private': false},
        ]),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile([
          {'name': 'feature.mp4', 'private': true},
        ]),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.hasSupportedVideoFile([
          {'name': 'feature.mkv', 'private': false},
        ]),
        isFalse,
      );
    });

    test('rejects unsafe Archive identifiers', () {
      expect(
        PublicDomainMovieSourceService.isSafeIdentifier('classic_film_1922'),
        isTrue,
      );
      expect(
        PublicDomainMovieSourceService.isSafeIdentifier('../private'),
        isFalse,
      );
      expect(
        PublicDomainMovieSourceService.isSafeIdentifier(''),
        isFalse,
      );
    });

    test('does not search TV episodes in the movie-only Archive catalogue', () async {
      final sources = await PublicDomainMovieSourceService.discover(
        'Example Series',
        isTv: true,
      );
      expect(sources, isEmpty);
    });
  });
}
