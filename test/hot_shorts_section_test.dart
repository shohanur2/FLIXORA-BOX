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


  test('Short TV subject type 7 is treated as an episodic series', () {
    final section = MovieBoxHomeSection.fromApi({
      'title': 'Hot Shorts TV',
      'items': [
        {
          'id': 'short-series-7',
          'title': 'Example Short Series',
          'detailPath': 'series/example-short',
          'cover': 'https://cdn.example.test/short.jpg',
          'year': '2026',
          'subjectType': 7,
        },
      ],
    });

    expect(section.items.single.movieBoxIsSeries, isTrue);
    expect(section.items.single.mediaType, 'tv');
    expect(section.items.single.movieBoxSubjectType, 7);
  });

  test('Short TV Drama subject type 3 is treated as an episodic series', () {
    final section = MovieBoxHomeSection.fromApi({
      'title': 'Hot Shorts TV',
      'items': [
        {
          'id': 'short-series-3',
          'title': 'Example Short Drama',
          'detailPath': 'series/example-short-drama',
          'cover': 'https://cdn.example.test/short-drama.jpg',
          'year': '2026',
          'subjectType': 3,
        },
      ],
    });

    expect(section.items.single.movieBoxIsSeries, isTrue);
    expect(section.items.single.mediaType, 'tv');
    expect(section.items.single.movieBoxSubjectType, 3);
  });

  test('Hot Shorts episode parser accepts object-shaped episode records', () {
    final episodes = MovieBoxShortEpisode.fromSeasons([
      {
        'seasonNumber': 2,
        'episodes': [
          {'ep': 2},
          {'episodeNumber': 1},
          {'number': 2},
        ],
      },
      {
        'season': 1,
        'episodeList': [
          {'episode': 3},
          1,
        ],
      },
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
