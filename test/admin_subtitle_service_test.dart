import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/player/admin_subtitle_service.dart';

void main() {
  group('AdminSubtitleTrack', () {
    test('maps joined language metadata into a readable subtitle track', () {
      final track = AdminSubtitleTrack.fromRow({
        'id': 12,
        'subtitle_url': 'https://cdn.example/subtitles/movie.bn.srt',
        'languages': {'name': 'Bangla', 'code': 'bn'},
      });

      expect(track.id, 12);
      expect(track.label, 'Bangla');
      expect(track.language, 'bn');
      expect(track.isValid, isTrue);
    });

    test('falls back to language code when language name is absent', () {
      final track = AdminSubtitleTrack.fromRow({
        'id': 13,
        'subtitle_url': 'https://cdn.example/movie.en.vtt',
        'languages': {'code': 'en'},
      });

      expect(track.label, 'en');
      expect(track.language, 'en');
    });

    test('rejects malformed, credentialed and non-http subtitle URLs', () {
      final invalid = [
        AdminSubtitleTrack.fromRow({
          'id': 1,
          'subtitle_url': 'javascript:alert(1)',
        }),
        AdminSubtitleTrack.fromRow({
          'id': 2,
          'subtitle_url': 'https://user:pass@cdn.example/subtitle.srt',
        }),
        AdminSubtitleTrack.fromRow({
          'id': 3,
          'subtitle_url': 'not a url',
        }),
      ];

      expect(invalid.every((track) => !track.isValid), isTrue);
    });
  });
}
