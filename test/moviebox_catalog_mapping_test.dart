import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  group('MovieBox catalogue mapping', () {
    final rawItem = <String, dynamic>{
      'id': 'mb-9001',
      'title': 'The Example Series',
      'isSeries': true,
      'detailPath': 'series/the-example',
      'cover': 'https://cdn.example.test/poster.jpg',
      'backdrop': 'https://cdn.example.test/backdrop.jpg',
      'rating': '8.3',
      'year': '2025',
      'genre': 'Drama, Thriller',
      'country': 'BD',
      'description': 'A sample series description.',
      'durationMin': 48,
      'subjectType': 2,
    };

    test('maps MovieBox series fields and playback identity', () {
      final movie = Movie.fromMovieBox(rawItem);

      expect(movie.source, 'moviebox');
      expect(movie.isMovieBox, isTrue);
      expect(movie.canAttemptPlayback, isTrue);
      expect(movie.mediaType, 'tv');
      expect(movie.movieBoxId, 'mb-9001');
      expect(movie.movieBoxDetailPath, 'series/the-example');
      expect(movie.movieBoxIsSeries, isTrue);
      expect(movie.movieBoxSubjectType, 2);
      expect(movie.posterUrl, rawItem['cover']);
      expect(movie.backdropUrl, rawItem['backdrop']);
      expect(movie.genres, ['Drama', 'Thriller']);
    });

    test('preserves MovieBox identity through the offline cache', () {
      final original = Movie.fromMovieBox(rawItem);
      final restored = Movie.fromCache(original.toJson());

      expect(restored.source, 'moviebox');
      expect(restored.movieBoxId, original.movieBoxId);
      expect(restored.movieBoxDetailPath, original.movieBoxDetailPath);
      expect(restored.movieBoxIsSeries, isTrue);
      expect(restored.toMovieBoxMap(), original.toMovieBoxMap());
    });

    test('maps and caches MovieBox home sections', () {
      final section = MovieBoxHomeSection.fromApi({
        'title': 'Trending Now',
        'ranked': true,
        'isBanner': true,
        'items': [rawItem],
      });

      expect(section.title, 'Trending Now');
      expect(section.ranked, isTrue);
      expect(section.isBanner, isTrue);
      expect(section.items, hasLength(1));

      final restored = MovieBoxHomeSection.fromCache(section.toJson());
      expect(restored.title, section.title);
      expect(restored.items.single.movieBoxId, 'mb-9001');
      expect(restored.isBanner, isTrue);
    });
  });
}
