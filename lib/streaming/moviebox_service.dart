import '../native/sparkbox_core.dart';

/// Single entry point for FLIXORA's MovieBox/WeFeed content system.
///
/// The native Rust core owns request signing, guest tokens, mobile/H5
/// fallback, parsing, stream resolution and subtitle discovery. Flutter
/// receives normalized JSON maps and remains responsible for UI, playback,
/// caching and downloads.
class MovieBoxService {
  MovieBoxService._();

  static Future<Map<String, dynamic>> version() => SparkBoxCore.version();

  static Future<void> enableSafeContentFilter() =>
      SparkBoxCore.setBlockAdult(true);

  static Future<List<Map<String, dynamic>>> home() => SparkBoxCore.home();

  static Future<List<String>> suggest(String query) =>
      SparkBoxCore.suggest(query);

  static Future<Map<String, dynamic>> search(
    String query, {
    int page = 1,
    int perPage = 20,
  }) =>
      SparkBoxCore.search(query, page: page, perPage: perPage);

  static Future<Map<String, dynamic>> detail(
    Map<String, dynamic> item,
  ) =>
      SparkBoxCore.detailRich(item);

  static Future<Map<String, dynamic>> playDetail(
    Map<String, dynamic> item,
  ) =>
      SparkBoxCore.playDetail(item);

  static Future<List<Map<String, dynamic>>> seasons(String subjectId) =>
      SparkBoxCore.seasons(subjectId);

  static Future<Map<String, dynamic>> streams(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required bool isSeries,
  }) =>
      SparkBoxCore.streams(
        detail,
        season: season,
        episode: episode,
        isSeries: isSeries,
      );
}
