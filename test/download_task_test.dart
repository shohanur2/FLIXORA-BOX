import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/downloads/download_task.dart';

void main() {
  group('DownloadTask', () {
    test('serializes and restores a paused download with its partial file', () {
      final task = DownloadTask(
        taskId: 'task-1',
        movieId: 42,
        tmdbId: 157336,
        title: 'Interstellar',
        poster: 'https://image.example/poster.jpg',
        videoUrl: 'https://cdn.example/interstellar.mp4',
        quality: '1080p',
        mediaType: 'movie',
        progress: 0.42,
        bytesReceived: 420,
        totalBytes: 1000,
        status: 'Paused',
        partialPath: '/private/interstellar.mp4.part',
      );

      final restored = DownloadTask.fromJson(task.toJson());

      expect(restored.taskId, 'task-1');
      expect(restored.movieId, 42);
      expect(restored.tmdbId, 157336);
      expect(restored.status, 'Paused');
      expect(restored.partialPath, '/private/interstellar.mp4.part');
      expect(restored.progress, 0.42);
    });

    test('formats season and episode in the download title', () {
      final task = DownloadTask(
        movieId: 9,
        title: 'Example Series',
        poster: '',
        mediaType: 'tv',
        seasonNumber: 2,
        episodeNumber: 4,
        episodeTitle: 'The Return',
      );

      expect(task.displayTitle, 'Example Series • S02 E04 • The Return');
    });

    test('keeps legacy completed download records readable', () {
      final task = DownloadTask.fromJson({
        'movieId': 7,
        'title': 'Legacy Movie',
        'poster': '',
        'status': 'Completed',
        'filePath': '/private/legacy.mp4',
      });

      expect(task.title, 'Legacy Movie');
      expect(task.status, 'Completed');
      expect(task.filePath, '/private/legacy.mp4');
      expect(task.taskId, isNotEmpty);
    });
  });
}
