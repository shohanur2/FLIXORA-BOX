import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/media_diagnostics.dart';

void main() {
  group('MediaDiagnostics', () {
    test('detects HLS and DASH from URL paths, not query strings', () {
      expect(
        MediaDiagnostics.containerFor('https://cdn.example/video.m3u8?token=x'),
        MediaContainer.hls,
      );
      expect(
        MediaDiagnostics.containerFor('https://cdn.example/manifest.mpd?x=1'),
        MediaContainer.dash,
      );
    });

    test('recognizes common FFmpeg/MPV video containers', () {
      expect(MediaDiagnostics.containerFor('https://cdn.example/movie.mp4'), MediaContainer.mp4);
      expect(MediaDiagnostics.containerFor('https://cdn.example/movie.mkv'), MediaContainer.matroska);
      expect(MediaDiagnostics.containerFor('https://cdn.example/movie.mov'), MediaContainer.quickTime);
      expect(MediaDiagnostics.containerFor('https://cdn.example/movie.webm'), MediaContainer.webm);
      expect(MediaDiagnostics.containerFor('https://cdn.example/movie.avi'), MediaContainer.avi);
    });

    test('only standalone direct files are eligible for direct downloads', () {
      expect(MediaDiagnostics.isDirectDownloadable('https://cdn.example/movie.mp4'), isTrue);
      expect(MediaDiagnostics.isDirectDownloadable('https://cdn.example/movie.mov'), isTrue);
      expect(MediaDiagnostics.isDirectDownloadable('https://cdn.example/master.m3u8'), isFalse);
      expect(MediaDiagnostics.isDirectDownloadable('https://cdn.example/manifest.mpd'), isFalse);
      expect(MediaDiagnostics.isDirectDownloadable('https://provider.example/watch/123'), isFalse);
    });

    test('rejects credentials and non-http schemes', () {
      expect(MediaDiagnostics.isHttpMediaUrl('file:///storage/video.mp4'), isFalse);
      expect(MediaDiagnostics.isHttpMediaUrl('https://user:pass@cdn.example/movie.mp4'), isFalse);
      expect(MediaDiagnostics.isHttpMediaUrl('https://cdn.example/movie.mp4'), isTrue);
    });

    test('maps common playback failures to useful messages', () {
      expect(MediaDiagnostics.friendlyError(Exception('HTTP 403 Forbidden')), contains('denied access'));
      expect(MediaDiagnostics.friendlyError(Exception('HTTP 404')), contains('could not be found'));
      expect(MediaDiagnostics.friendlyError(Exception('connection timed out')), contains('too long'));
    });
  });
}
