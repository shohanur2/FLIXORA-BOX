
import 'dart:convert';
import 'package:http/http.dart' as http;

class ArchiveMovie {
  final String identifier;
  final String title;
  final String year;
  final String description;
  final String? videoUrl;

  const ArchiveMovie({
    required this.identifier,
    required this.title,
    required this.year,
    required this.description,
    this.videoUrl,
  });
}

class ArchiveService {
  static const String baseUrl = 'https://archive.org';

  static Future<List<ArchiveMovie>> searchMovies(
    String query,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/advancedsearch.php',
    ).replace(queryParameters: {
      'q': 'mediatype:movies AND title:(${query.trim()})',
      'fl[]': 'identifier,title,year,description',
      'rows': '20',
      'page': '1',
      'output': 'json',
    });

    final response = await http.get(uri).timeout(
      const Duration(seconds: 30),
    );

    if (response.statusCode != 200) {
      throw Exception('Archive search failed');
    }

    final data = jsonDecode(response.body);
    final docs = data['response']['docs'] as List? ?? [];

    return docs.map((item) {
      return ArchiveMovie(
        identifier: item['identifier']?.toString() ?? '',
        title: item['title']?.toString() ?? 'Unknown',
        year: item['year']?.toString() ?? 'N/A',
        description:
            item['description']?.toString() ?? '',
      );
    }).where((movie) => movie.identifier.isNotEmpty).toList();
  }

  static Future<ArchiveMovie> getMovieDetails(
    ArchiveMovie movie,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/metadata/${movie.identifier}',
    );

    final response = await http.get(uri).timeout(
      const Duration(seconds: 30),
    );

    if (response.statusCode != 200) {
      throw Exception('Could not load video information');
    }

    final data = jsonDecode(response.body);
    final metadata = data['metadata'] ?? {};
    final files = data['files'] as List? ?? [];

    // Only identify MP4 files here.
    // Playback/download must be limited to files
    // whose rights permit that use.
    final mp4Files = files.where((file) {
      final name = file['name']?.toString().toLowerCase() ?? '';
      return name.endsWith('.mp4');
    }).toList();

    String? videoUrl;

    if (mp4Files.isNotEmpty) {
      final fileName = mp4Files.first['name'].toString();
      videoUrl =
          '$baseUrl/download/${movie.identifier}/${Uri.encodeComponent(fileName)}';
    }

    return ArchiveMovie(
      identifier: movie.identifier,
      title: metadata['title']?.toString() ?? movie.title,
      year: metadata['year']?.toString() ?? movie.year,
      description:
          metadata['description']?.toString() ?? movie.description,
      videoUrl: videoUrl,
    );
  }
}
