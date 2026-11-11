import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'download_task.dart';
import 'manifest_download_manager.dart';

class DownloadFileInfo {
  const DownloadFileInfo({
    this.sizeBytes,
    this.contentType,
    required this.extension,
  });

  final int? sizeBytes;
  final String? contentType;
  final String extension;
}

class DownloadManager {
  DownloadManager._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: Duration.zero,
      followRedirects: true,
      maxRedirects: 8,
    ),
  );

  static final Map<String, CancelToken> _activeTokens = {};
  static final Set<String> _pauseRequests = <String>{};
  static final Set<String> _cancelRequests = <String>{};

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.m4v',
    '.mkv',
    '.webm',
    '.mov',
    '.avi',
  };

  static String formatBytes(int bytes) {
    if (bytes <= 0) return 'Size unavailable';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  static Uri? safeDownloadUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8') ||
        path.endsWith('.mpd') ||
        path.endsWith('.m3u') ||
        path.endsWith('.mp4.m3u8')) {
      return null;
    }
    return uri;
  }

  static String? extensionFromUrl(String rawUrl) {
    final uri = safeDownloadUri(rawUrl);
    if (uri == null) return null;
    final path = uri.path.toLowerCase();
    for (final extension in _videoExtensions) {
      if (path.endsWith(extension)) return extension;
    }
    return null;
  }

  static bool isSupportedVideoUrl(String rawUrl) =>
      extensionFromUrl(rawUrl) != null;

  static bool _isRejectedContentType(String? raw) {
    final type = (raw ?? '').split(';').first.trim().toLowerCase();
    return type == 'text/html' ||
        type == 'application/json' ||
        type == 'text/plain' ||
        type.contains('mpegurl') ||
        type.contains('dash+xml') ||
        type.contains('vnd.apple');
  }

  static bool _isVideoContentType(String? raw) {
    final type = (raw ?? '').split(';').first.trim().toLowerCase();
    if (type.isEmpty) return false;
    if (_isRejectedContentType(type)) return false;
    return type.startsWith('video/') ||
        type == 'application/octet-stream' ||
        type == 'application/mp4' ||
        type == 'application/x-matroska';
  }

  static String _extensionFromContentType(String? raw) {
    final type = (raw ?? '').split(';').first.trim().toLowerCase();
    switch (type) {
      case 'video/mp4':
      case 'application/mp4':
        return '.mp4';
      case 'video/webm':
        return '.webm';
      case 'video/x-matroska':
      case 'application/x-matroska':
        return '.mkv';
      case 'video/quicktime':
        return '.mov';
      case 'video/x-msvideo':
        return '.avi';
      case 'video/x-m4v':
        return '.m4v';
      default:
        return '.mp4';
    }
  }

  static int? _contentLength(Headers headers) {
    final raw = headers.value('content-length');
    final value = int.tryParse(raw ?? '');
    return value != null && value > 0 ? value : null;
  }

  static int? _rangeTotal(Headers headers) {
    final raw = headers.value('content-range') ?? '';
    final match = RegExp(r'bytes\s+\d+-\d+/(\d+)', caseSensitive: false)
        .firstMatch(raw);
    final value = int.tryParse(match?.group(1) ?? '');
    return value != null && value > 0 ? value : null;
  }

  static Future<DownloadFileInfo?> inspectRemoteFile(String rawUrl) async {
    final uri = safeDownloadUri(rawUrl);
    if (uri == null) return null;
    final knownExtension = extensionFromUrl(rawUrl);

    try {
      final response = await _dio
          .head(
            uri.toString(),
            options: Options(
              headers: const {'Accept-Encoding': 'identity'},
              followRedirects: true,
            ),
          )
          .timeout(const Duration(seconds: 9));

      final contentType = response.headers.value('content-type');
      if (_isRejectedContentType(contentType)) return null;
      final isVideo = _isVideoContentType(contentType);
      if (isVideo || knownExtension != null) {
        return DownloadFileInfo(
          sizeBytes: _contentLength(response.headers),
          contentType: contentType,
          extension: knownExtension ?? _extensionFromContentType(contentType),
        );
      }
    } catch (_) {
      // Some storage providers block HEAD. A known direct-file extension is
      // still eligible; the actual response is validated before saving.
    }

    if (knownExtension != null) {
      return DownloadFileInfo(extension: knownExtension);
    }

    final token = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: const {
            'Range': 'bytes=0-0',
            'Accept-Encoding': 'identity',
          },
        ),
        cancelToken: token,
      ).timeout(const Duration(seconds: 9));

      final contentType = response.headers.value('content-type');
      if (!_isVideoContentType(contentType)) return null;
      return DownloadFileInfo(
        sizeBytes: _rangeTotal(response.headers) ??
            _contentLength(response.headers),
        contentType: contentType,
        extension: _extensionFromContentType(contentType),
      );
    } catch (_) {
      return null;
    } finally {
      token.cancel('Remote file inspection complete');
    }
  }

  static Future<int?> getRemoteFileSize(String url) async =>
      (await inspectRemoteFile(url))?.sizeBytes;

  /// Resolves direct files and finite HLS/DASH manifests into selectable
  /// download options. Embed pages are deliberately not treated as media.
  static Future<List<Map<String, String>>> inspectDownloadSources(
    String rawUrl, {
    String? qualityLabel,
  }) async {
    final manifestOptions = await ManifestDownloadManager.inspect(rawUrl);
    if (manifestOptions.isNotEmpty) {
      return manifestOptions.map((option) => option.toMap()).toList();
    }

    final info = await inspectRemoteFile(rawUrl);
    if (info == null) return const [];
    return [
      <String, String>{
        'quality': qualityLabel?.trim().isNotEmpty == true
            ? qualityLabel!.trim()
            : 'Original',
        'video_url': rawUrl.trim(),
        'download_type': 'direct',
        'size_bytes': info.sizeBytes?.toString() ?? '',
      },
    ];
  }

  static Future<int> getTaskStorageBytes(DownloadTask task) async {
    final directoryPath = task.downloadDirectory;
    if (directoryPath != null && directoryPath.isNotEmpty) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) return 0;
      var total = 0;
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File && !entity.path.endsWith('.part')) {
          total += await entity.length();
        }
      }
      return total;
    }
    final path = task.filePath;
    if (path == null) return 0;
    final file = File(path);
    return await file.exists() ? file.length() : 0;
  }

  static Future<void> download({
    required DownloadTask task,
    required void Function(int received, int total) onProgress,
    required Future<void> Function(String path) onComplete,
    required void Function(String message) onError,
    void Function()? onStateChanged,
  }) async {
    if (task.downloadType == 'hls' || task.downloadType == 'dash') {
      await _downloadManifest(
        task: task,
        onProgress: onProgress,
        onComplete: onComplete,
        onError: onError,
        onStateChanged: onStateChanged,
      );
      return;
    }

    final uri = safeDownloadUri(task.videoUrl);
    if (uri == null) {
      task.status = 'Failed';
      task.errorMessage =
          'This is a streaming/embed link, not a direct downloadable video file.';
      onError(task.errorMessage!);
      onStateChanged?.call();
      return;
    }

    final token = CancelToken();
    _activeTokens[task.taskId] = token;
    _pauseRequests.remove(task.taskId);
    _cancelRequests.remove(task.taskId);

    File? partialFile;
    IOSink? sink;

    try {
      final info = await inspectRemoteFile(task.videoUrl);
      if (info == null) {
        throw StateError(
          'This source is not a direct video file. HLS, DASH and embed links cannot be saved as a video file.',
        );
      }
      if (info.sizeBytes != null) task.totalBytes = info.sizeBytes!;

      final directory = await getApplicationDocumentsDirectory();
      final safeName = task.displayTitle
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final extension = info.extension;
      task.filePath ??=
          '${directory.path}/${safeName}_${task.taskId}$extension';
      task.partialPath ??= '${task.filePath}.part';
      partialFile = File(task.partialPath!);

      final completedFile = File(task.filePath!);
      if (await completedFile.exists() && await completedFile.length() > 0) {
        task
          ..status = 'Completed'
          ..progress = 1
          ..bytesReceived = await completedFile.length()
          ..totalBytes = await completedFile.length()
          ..partialPath = null
          ..errorMessage = null;
        await onComplete(task.filePath!);
        onStateChanged?.call();
        return;
      }

      var offset = await partialFile.exists() ? await partialFile.length() : 0;
      if (task.totalBytes > 0 && offset >= task.totalBytes && offset > 0) {
        await partialFile.rename(task.filePath!);
        task
          ..status = 'Completed'
          ..progress = 1
          ..bytesReceived = offset
          ..totalBytes = offset
          ..partialPath = null
          ..errorMessage = null;
        await onComplete(task.filePath!);
        onStateChanged?.call();
        return;
      }
      task
        ..status = 'Downloading'
        ..errorMessage = null
        ..bytesReceived = offset;
      onStateChanged?.call();

      final headers = <String, String>{'Accept-Encoding': 'identity'};
      if (offset > 0) headers['Range'] = 'bytes=$offset-';

      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          followRedirects: true,
        ),
        cancelToken: token,
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200 && statusCode != 206) {
        throw StateError('The video host returned HTTP $statusCode.');
      }

      final contentType = response.headers.value('content-type');
      if (_isRejectedContentType(contentType) ||
          (contentType != null &&
              contentType.isNotEmpty &&
              !_isVideoContentType(contentType))) {
        throw StateError(
          'The source returned a webpage instead of a video file.',
        );
      }

      var append = offset > 0 && statusCode == 206;
      if (append) {
        final rangeStart = RegExp(r'bytes\s+(\d+)-', caseSensitive: false)
            .firstMatch(response.headers.value('content-range') ?? '');
        final serverOffset = int.tryParse(rangeStart?.group(1) ?? '');
        if (serverOffset != null && serverOffset != offset) {
          throw StateError('The video host returned an invalid resume range.');
        }
      } else if (offset > 0 && statusCode == 200) {
        // The host ignored Range. Restart cleanly rather than corrupting the
        // file by appending a second full copy.
        offset = 0;
        await partialFile.writeAsBytes(const <int>[], flush: true);
      }

      final contentLength = _contentLength(response.headers);
      final total = _rangeTotal(response.headers) ??
          (contentLength == null ? 0 : offset + contentLength);
      if (total > 0) task.totalBytes = total;

      var received = offset;
      sink = partialFile.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );

      await for (final chunk in response.data!.stream) {
        if (token.isCancelled) throw StateError('Download interrupted.');
        sink.add(chunk);
        received += chunk.length;
        task.bytesReceived = received;
        if (task.totalBytes > 0) {
          task.progress =
              (received / task.totalBytes).clamp(0.0, 1.0).toDouble();
        }
        onProgress(received, task.totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;
      if (token.isCancelled) throw StateError('Download interrupted.');

      if (task.totalBytes > 0 && received < task.totalBytes) {
        throw StateError('The download ended before the full video arrived.');
      }

      if (await completedFile.exists()) await completedFile.delete();
      await partialFile.rename(task.filePath!);
      task
        ..status = 'Completed'
        ..progress = 1
        ..bytesReceived = received
        ..totalBytes = received
        ..partialPath = null
        ..errorMessage = null;
      await onComplete(task.filePath!);
      onStateChanged?.call();
    } on DioException catch (error) {
      if (sink != null) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
        sink = null;
      }
      if (_cancelRequests.remove(task.taskId)) {
        await _removePartial(partialFile);
        task
          ..status = 'Cancelled'
          ..progress = 0
          ..bytesReceived = 0
          ..errorMessage = null;
        onStateChanged?.call();
      } else if (_pauseRequests.remove(task.taskId) || token.isCancelled) {
        task
          ..status = 'Paused'
          ..errorMessage = null;
        onStateChanged?.call();
      } else {
        task
          ..status = 'Failed'
          ..errorMessage = _friendlyError(error);
        onError(task.errorMessage!);
        onStateChanged?.call();
      }
    } catch (error) {
      if (sink != null) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
        sink = null;
      }
      if (_cancelRequests.remove(task.taskId)) {
        await _removePartial(partialFile);
        task
          ..status = 'Cancelled'
          ..progress = 0
          ..bytesReceived = 0
          ..errorMessage = null;
        onStateChanged?.call();
      } else if (_pauseRequests.remove(task.taskId) || token.isCancelled) {
        task
          ..status = 'Paused'
          ..errorMessage = null;
        onStateChanged?.call();
      } else {
        task
          ..status = 'Failed'
          ..errorMessage = error is StateError
              ? error.message
              : 'Download failed. Please try again.';
        onError(task.errorMessage!);
        onStateChanged?.call();
      }
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      _activeTokens.remove(task.taskId);
      _pauseRequests.remove(task.taskId);
      _cancelRequests.remove(task.taskId);
    }
  }

  static Future<void> _downloadManifest({
    required DownloadTask task,
    required void Function(int received, int total) onProgress,
    required Future<void> Function(String path) onComplete,
    required void Function(String message) onError,
    void Function()? onStateChanged,
  }) async {
    final token = CancelToken();
    _activeTokens[task.taskId] = token;
    _pauseRequests.remove(task.taskId);
    _cancelRequests.remove(task.taskId);

    try {
      task
        ..status = 'Downloading'
        ..errorMessage = null;
      onStateChanged?.call();

      final path = await ManifestDownloadManager.download(
        task: task,
        cancelToken: token,
        onProgress: () {
          onProgress(task.bytesReceived, task.totalBytes);
          onStateChanged?.call();
        },
      );
      if (token.isCancelled) {
        throw DioException(
          requestOptions: RequestOptions(path: task.videoUrl),
          type: DioExceptionType.cancel,
          message: 'Download interrupted.',
        );
      }
      task
        ..status = 'Completed'
        ..progress = 1
        ..filePath = path
        ..partialPath = null
        ..errorMessage = null;
      await onComplete(path);
      onStateChanged?.call();
    } on DioException catch (error) {
      if (_cancelRequests.remove(task.taskId)) {
        await _removeTaskPartial(task);
        task
          ..status = 'Cancelled'
          ..progress = 0
          ..bytesReceived = 0
          ..totalBytes = 0
          ..completedSegments = 0
          ..errorMessage = null
          ..filePath = null;
        onStateChanged?.call();
      } else if (_pauseRequests.remove(task.taskId) || token.isCancelled) {
        task
          ..status = 'Paused'
          ..errorMessage = null;
        onStateChanged?.call();
      } else {
        task
          ..status = 'Failed'
          ..errorMessage = _friendlyError(error);
        onError(task.errorMessage!);
        onStateChanged?.call();
      }
    } catch (error) {
      if (_cancelRequests.remove(task.taskId)) {
        await _removeTaskPartial(task);
        task
          ..status = 'Cancelled'
          ..progress = 0
          ..bytesReceived = 0
          ..totalBytes = 0
          ..completedSegments = 0
          ..errorMessage = null
          ..filePath = null;
        onStateChanged?.call();
      } else if (_pauseRequests.remove(task.taskId) || token.isCancelled) {
        task
          ..status = 'Paused'
          ..errorMessage = null;
        onStateChanged?.call();
      } else {
        task
          ..status = 'Failed'
          ..errorMessage = error is StateError
              ? error.message
              : 'Manifest download failed. Please try again.';
        onError(task.errorMessage!);
        onStateChanged?.call();
      }
    } finally {
      _activeTokens.remove(task.taskId);
      _pauseRequests.remove(task.taskId);
      _cancelRequests.remove(task.taskId);
    }
  }

  static Future<void> _removeTaskPartial(DownloadTask task) async {
    await _deletePath(task.downloadDirectory);
    await _deletePath(task.partialPath);
    task
      ..downloadDirectory = null
      ..partialPath = null;
  }

  static Future<void> _deletePath(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(path).delete();
      }
    } catch (_) {}
  }

  static String _friendlyError(DioException error) {
    if (error.response?.statusCode == 403) {
      return 'The video link expired or access was denied. Refresh the source and try again.';
    }
    if (error.response?.statusCode == 404) {
      return 'The video file was not found on the host.';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return 'Connection timed out. You can resume the download.';
    }
    return 'Download failed. Check the connection and try again.';
  }

  static void pause(DownloadTask task) {
    if (task.status != 'Downloading') return;
    _pauseRequests.add(task.taskId);
    _activeTokens[task.taskId]?.cancel('pause');
  }

  static Future<void> cancel(DownloadTask task) async {
    _cancelRequests.add(task.taskId);
    final token = _activeTokens[task.taskId];
    if (token != null) {
      token.cancel('cancel');
      return;
    }
    await _removeTaskPartial(task);
    task
      ..status = 'Cancelled'
      ..filePath = null
      ..progress = 0
      ..bytesReceived = 0
      ..errorMessage = null;
  }

  static Future<void> _removePartial(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> deleteTaskFiles(DownloadTask task) async {
    await _deletePath(task.downloadDirectory);
    await _deletePath(task.filePath);
    await _deletePath(task.partialPath);
    task
      ..downloadDirectory = null
      ..filePath = null
      ..partialPath = null;
  }
}
