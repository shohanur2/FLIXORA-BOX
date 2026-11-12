import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/catalog_priority_policy.dart';

void main() {
  group('CatalogPriorityPolicy', () {
    test('prefers MovieBox over an Admin fallback match', () {
      expect(
        CatalogPriorityPolicy.preferMovieBox('Admin source', 'MovieBox source'),
        'MovieBox source',
      );
    });

    test('keeps an unpublished title when it exists in MovieBox', () {
      expect(
        CatalogPriorityPolicy.shouldHideUnpublished(
          isMovieBox: true,
          isUnpublished: true,
        ),
        isFalse,
      );
    });

    test('hides an unpublished Admin-only title', () {
      expect(
        CatalogPriorityPolicy.shouldHideUnpublished(
          isMovieBox: false,
          isUnpublished: true,
        ),
        isTrue,
      );
    });

    test('keeps a published Admin fallback title', () {
      expect(
        CatalogPriorityPolicy.shouldHideUnpublished(
          isMovieBox: false,
          isUnpublished: false,
        ),
        isFalse,
      );
    });
  });
}
