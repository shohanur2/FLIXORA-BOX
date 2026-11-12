import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/catalog_source_policy.dart';

void main() {
  group('CatalogSourcePolicy', () {
    test('MovieBox wins over a published Admin duplicate', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: 'moviebox',
        publishedAdminFallback: 'admin',
      );

      expect(selected, 'moviebox');
    });

    test('published Admin is used only when MovieBox has no match', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: null,
        publishedAdminFallback: 'admin',
      );

      expect(selected, 'admin');
    });

    test('returns unavailable when neither source has a match', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: null,
        publishedAdminFallback: null,
      );

      expect(selected, isNull);
    });

    test('MovieBox replaces only its duplicate and preserves other card order', () {
      final ordered = CatalogSourcePolicy.preferMovieBoxDuplicates<String>(
        [
          'first',
          'admin:interstellar',
          'middle',
          'moviebox:interstellar',
          'last',
        ],
        isMovieBox: (source) => source.startsWith('moviebox:'),
        matches: (movieBoxItem, candidate) =>
            movieBoxItem.split(':').last == candidate.split(':').last,
      );

      expect(
        ordered,
        ['first', 'middle', 'moviebox:interstellar', 'last'],
      );
    });

    test('only Admin rows are sent to publication visibility checks', () {
      final candidates = CatalogSourcePolicy.adminCandidates<String>(
        ['tmdb', 'moviebox', 'admin'],
        isAdmin: (source) => source == 'admin',
      );

      expect(candidates, ['admin']);
    });

    test('Admin visibility key identifies the exact Admin row', () {
      expect(
        CatalogSourcePolicy.adminVisibilityKey(
          isAdmin: true,
          sourceId: 42,
        ),
        'admin:id:42',
      );
      expect(
        CatalogSourcePolicy.adminVisibilityKey(
          isAdmin: false,
          sourceId: 42,
        ),
        isNull,
      );
    });

    test('unpublishing Admin does not block a matching MovieBox title', () {
      final blockedKeys = {'admin:id:42'};

      expect(
        CatalogSourcePolicy.isAdminBlocked(
          isAdmin: true,
          visibilityKey: 'admin:id:42',
          blockedKeys: blockedKeys,
        ),
        isTrue,
      );
      expect(
        CatalogSourcePolicy.isAdminBlocked(
          isAdmin: false,
          visibilityKey: 'admin:id:42',
          blockedKeys: blockedKeys,
        ),
        isFalse,
      );
      expect(
        CatalogSourcePolicy.isAdminBlocked(
          isAdmin: false,
          visibilityKey: null,
          blockedKeys: blockedKeys,
        ),
        isFalse,
      );
    });
  });
}
