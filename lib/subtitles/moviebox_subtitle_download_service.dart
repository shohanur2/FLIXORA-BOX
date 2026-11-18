import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads only MovieBox-provided subtitle files into FLIXORA's private
/// subtitle cache. This does not enqueue or alter video download tasks.
class MovieBoxSubtitleDownloadService {
  MovieBoxSubtitleDownloadService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 35),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: true,
    ),
  );

  static Future<File> download({
    required String url,
    required String fileName,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid MovieBox subtitle URL.');
    }

    final response = await _dio.get<List<int>>(
      uri.toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('MovieBox returned an empty subtitle file.');
    }

    final safeName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      throw const FormatException('Invalid subtitle file name.');
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/flixora_subtitles');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
