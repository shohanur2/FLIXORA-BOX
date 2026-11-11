import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/downloads/download_manager.dart';

void main() {
  group('DownloadManager direct-file validation', () {
    test('accepts supported direct video file extensions', () {
      for (final url in [
        'https://cdn.example/movie.mp4',
        'https://cdn.example/movie.mkv?token=abc',
        'https://cdn.example/movie.webm',
        'https://cdn.example/movie.mov',
        'https://cdn.example/movie.avi',
        'https://cdn.example/movie.m4v',
      ]) {
        expect(DownloadManager.isSupportedVideoUrl(url), isTrue, reason: url);
      }
    });

    test('rejects HLS, DASH, embed pages and unsupported schemes', () {
      for (final url in [
        'https://cdn.example/master.m3u8',
        'https://cdn.example/manifest.mpd',
        'https://player.example/embed/123',
        'javascript:alert(1)',
        'https://user:pass@cdn.example/movie.mp4',
      ]) {
        expect(DownloadManager.isSupportedVideoUrl(url), isFalse, reason: url);
      }
    });

    test('normalizes safe URLs and rejects credentials', () {
      expect(
        DownloadManager.safeDownloadUri('https://cdn.example/movie.mp4'),
        isNotNull,
      );
      expect(
        DownloadManager.safeDownloadUri('https://user:pass@cdn.example/movie.mp4'),
        isNull,
      );
    });

    test('formats file sizes for the download list', () {
      expect(DownloadManager.formatBytes(1024), '1.0 KB');
      expect(DownloadManager.formatBytes(1048576), '1.0 MB');
      expect(DownloadManager.formatBytes(0), 'Size unavailable');
    });
  });
}
