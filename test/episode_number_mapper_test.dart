import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/episode_number_mapper.dart';

void main() {
  group('EpisodeNumberMapper', () {
    final seasons = <Map<String, dynamic>>[
      {'season_number': 0, 'episode_count': 3},
      {'season_number': 2, 'episode_count': 8},
      {'season_number': 1, 'episode_count': 12},
      {'season_number': 3, 'episode_count': 10},
    ];

    test('maps later seasons to a continuous absolute episode index', () {
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 2,
          episodeNumber: 4,
        ),
        16,
      );
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 3,
          episodeNumber: 2,
        ),
        22,
      );
    });

    test('keeps season one episode numbering unchanged', () {
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 1,
          episodeNumber: 7,
        ),
        7,
      );
    });

    test('does not count specials or invent mappings for missing seasons', () {
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        2,
      );
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 4,
          episodeNumber: 1,
        ),
        isNull,
      );
    });

    test('rejects invalid episode coordinates and out-of-range episodes', () {
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 2,
          episodeNumber: 0,
        ),
        isNull,
      );
      expect(
        EpisodeNumberMapper.toAbsoluteEpisodeNumber(
          seasons: seasons,
          seasonNumber: 2,
          episodeNumber: 9,
        ),
        isNull,
      );
    });
  });
}
