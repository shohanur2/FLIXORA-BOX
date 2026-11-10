import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/main.dart';

void main() {
  Movie buildMovie({
    int id = 157336,
    int tmdbId = 157336,
    String mediaType = 'movie',
    String videoUrl = '',
  }) {
    return Movie(
      id: id,
      tmdbId: tmdbId,
      title: 'Interstellar',
      year: '2014',
      overview: 'A test movie.',
      poster: '',
      backdrop: '',
      rating: 8.6,
      releaseDate: '2014-11-07',
      videoUrl: videoUrl,
      mediaType: mediaType,
    );
  }

  group('Media title playback eligibility', () {
    test('TMDB movie without a direct URL can use provider fallback', () {
      final movie = buildMovie();

      expect(movie.hasPlayableVideoUrl, isFalse);
      expect(movie.canAttemptPlayback, isTrue);
    });

    test('direct video remains playable without a TMDB ID', () {
      final movie = buildMovie(
        id: -12,
        tmdbId: 0,
        videoUrl: 'https://cdn.example.com/movie.mp4',
      );

      expect(movie.hasPlayableVideoUrl, isTrue);
      expect(movie.canAttemptPlayback, isTrue);
    });

    test('movie without a direct URL or TMDB ID is not playable', () {
      final movie = buildMovie(id: -12, tmdbId: 0);

      expect(movie.canAttemptPlayback, isFalse);
    });

    test('TV shows, web series, dramas and anime can use the TV route', () {
      final title = buildMovie(mediaType: 'tv');

      expect(title.hasPlayableVideoUrl, isFalse);
      expect(title.canAttemptPlayback, isTrue);
    });

    test('Supabase TV content retains its media type', () {
      final title = Movie.fromSupabase({
        'id': 12,
        'tmdb_id': 1399,
        'title': 'Example Series',
        'media_type': 'tv',
      });

      expect(title.mediaType, 'tv');
      expect(title.canAttemptPlayback, isTrue);
    });

    test('legacy Supabase rows remain movies by default', () {
      final title = Movie.fromSupabase({
        'id': 13,
        'tmdb_id': 157336,
        'title': 'Interstellar',
      });

      expect(title.mediaType, 'movie');
    });
  });
}
