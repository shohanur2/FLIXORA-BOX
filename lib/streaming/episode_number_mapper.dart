/// Maps TMDB season/episode coordinates to an absolute episode number.
///
/// This is useful for anime catalogs whose episode resolvers use one continuous
/// episode index even when TMDB splits the title into multiple seasons. Specials
/// (season 0) are intentionally excluded unless a provider supplies an explicit
/// mapping, because specials are not consistently numbered across catalogs.
class EpisodeNumberMapper {
  EpisodeNumberMapper._();

  static int? toAbsoluteEpisodeNumber({
    required List<Map<String, dynamic>> seasons,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    if (seasonNumber <= 0 || episodeNumber <= 0) return null;

    final normalized = <({int season, int count})>[];
    for (final item in seasons) {
      final rawSeason = item['season_number'];
      final rawCount = item['episode_count'];
      final season = rawSeason is num
          ? rawSeason.toInt()
          : int.tryParse('$rawSeason') ?? 0;
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse('$rawCount') ?? 0;
      if (season > 0 && count > 0) {
        normalized.add((season: season, count: count));
      }
    }

    normalized.sort((a, b) => a.season.compareTo(b.season));
    final targetIndex = normalized.indexWhere((item) => item.season == seasonNumber);
    if (targetIndex < 0) return null;

    final target = normalized[targetIndex];
    if (episodeNumber > target.count) return null;

    var offset = 0;
    for (var index = 0; index < targetIndex; index++) {
      offset += normalized[index].count;
    }
    return offset + episodeNumber;
  }
}
