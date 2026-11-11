import 'package:supabase_flutter/supabase_flutter.dart';

/// An Admin-managed subtitle source stored in public.movie_subtitles.
class AdminSubtitleTrack {
  const AdminSubtitleTrack({
    required this.id,
    required this.label,
    required this.language,
    required this.url,
  });

  final int id;
  final String label;
  final String language;
  final String url;

  bool get isValid {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }

  factory AdminSubtitleTrack.fromRow(Map<String, dynamic> row) {
    final rawLanguage = row['languages'];
    final languageRow = rawLanguage is Map
        ? Map<String, dynamic>.from(rawLanguage)
        : const <String, dynamic>{};
    final name = (languageRow['name'] ?? '').toString().trim();
    final code = (languageRow['code'] ?? '').toString().trim();
    final language = name.isNotEmpty ? name : code;
    final id = int.tryParse((row['id'] ?? '').toString()) ?? 0;
    return AdminSubtitleTrack(
      id: id,
      label: language.isNotEmpty ? language : 'Subtitle',
      language: code.isNotEmpty ? code : language,
      url: (row['subtitle_url'] ?? '').toString().trim(),
    );
  }
}

class AdminSubtitleService {
  AdminSubtitleService._();

  /// RLS exposes subtitles only for published titles to visitor sessions.
  /// The Admin panel remains responsible for adding/editing subtitle records.
  static Future<List<AdminSubtitleTrack>> forMovie({
    required SupabaseClient? client,
    required int movieId,
  }) async {
    if (client == null || movieId <= 0) return const [];

    try {
      final rows = await client
          .from('movie_subtitles')
          .select('id, subtitle_url, languages(name,code)')
          .eq('movie_id', movieId);

      return (rows as List)
          .whereType<Map>()
          .map((row) => AdminSubtitleTrack.fromRow(
                Map<String, dynamic>.from(row),
              ))
          .where((track) => track.isValid)
          .toList(growable: false);
    } catch (_) {
      // Subtitles are optional and must never prevent the video from playing.
      return const [];
    }
  }
}
