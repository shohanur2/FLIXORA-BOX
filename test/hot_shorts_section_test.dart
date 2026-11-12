import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  test('MovieBox Hot Shorts episode lists preserve season and part numbers', () {
    final episodes = MovieBoxShortEpisode.fromSeasons([
      {'se': 2, 'episodes': [2, 1, 2]},
      {'se': 1, 'episodes': [1, 3]},
    ]);

    expect(
      episodes.map((episode) => episode.label).toList(),
      ['S1 · E1', 'S1 · E3', 'S2 · E1', 'S2 · E2'],
    );
  });

  test('MovieBox Hot Shorts TV is recognized as a separate feed', () {
    final section = MovieBoxHomeSection.fromApi({
      'title': 'Hot Shorts TV',
      'items': [
        {
          'id': 'short-1',
          'title': 'Example Short',
          'isSeries': true,
          'detailPath': 'series/example-short',
          'cover': 'https://cdn.example.test/short.jpg',
          'year': '2026',
          'subjectType': 2,
        },
      ],
    });

    expect(section.isHotShorts, isTrue);
    expect(section.items.single.isMovieBox, isTrue);
    expect(section.items.single.movieBoxIsSeries, isTrue);
  });
}
