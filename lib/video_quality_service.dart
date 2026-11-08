
import 'package:supabase_flutter/supabase_flutter.dart';

class VideoQuality {
  final String quality;
  final String? videoUrl;
  final String? storagePath;

  const VideoQuality({
    required this.quality,
    this.videoUrl,
    this.storagePath,
  });

  factory VideoQuality.fromMap(Map<String, dynamic> map) {
    return VideoQuality(
      quality: map['quality']?.toString() ?? '',
      videoUrl: map['video_url']?.toString(),
      storagePath: map['storage_path']?.toString(),
    );
  }

  String? get playableUrl {
    final url = videoUrl?.trim();
    if (url != null && url.isNotEmpty) return url;
    return null;
  }
}

class VideoQualityService {
  VideoQualityService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const List<String> supportedQualities = [
    '240p',
    '360p',
    '480p',
    '720p',
    '1080p',
    '1440p',
    '2160p',
  ];

  /// Loads all available video qualities for a movie.
  Future<List<VideoQuality>> getQualities(String movieId) async {
    final id = movieId.trim();

    if (id.isEmpty) {
      throw ArgumentError('Movie ID cannot be empty.');
    }

    final response = await _client
        .from('movie_video_qualities')
        .select('quality, video_url, storage_path')
        .eq('movie_id', id);

    final qualities = (response as List)
        .map(
          (item) => VideoQuality.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .where((item) => item.quality.isNotEmpty)
        .toList();

    final order = {
      for (var i = 0; i < supportedQualities.length; i++)
        supportedQualities[i]: i,
    };

    qualities.sort(
      (a, b) => (order[a.quality] ?? 999)
          .compareTo(order[b.quality] ?? 999),
    );

    return qualities;
  }

  /// Returns the first quality that has a direct playable URL.
  VideoQuality? getDefaultQuality(List<VideoQuality> qualities) {
    for (final quality in qualities) {
      if (quality.playableUrl != null) {
        return quality;
      }
    }
    return null;
  }

  /// Converts database quality names into display labels.
  static String getDisplayName(String quality) {
    switch (quality) {
      case '1440p':
        return '2K';
      case '2160p':
        return '4K';
      default:
        return quality;
    }
  }
}
