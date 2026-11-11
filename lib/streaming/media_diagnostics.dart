/// Media URL classification and user-facing playback diagnostics for FLIXORA.
///
/// media_kit uses libmpv/FFmpeg for demuxing and decoding. This helper does not
/// guess a codec from a filename; it only identifies common container/protocol
/// hints and leaves unknown URLs to MPV's content probing.
enum MediaContainer {
  hls,
  dash,
  mp4,
  matroska,
  quickTime,
  webm,
  avi,
  mpegTs,
  flv,
  wmv,
  threeGp,
  unknown,
}

class MediaDiagnostics {
  MediaDiagnostics._();

  static MediaContainer containerFor(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return MediaContainer.unknown;
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8') || path.endsWith('.m3u')) {
      return MediaContainer.hls;
    }
    if (path.endsWith('.mpd')) return MediaContainer.dash;
    if (path.endsWith('.mp4') || path.endsWith('.m4v')) {
      return MediaContainer.mp4;
    }
    if (path.endsWith('.mkv') || path.endsWith('.mka')) {
      return MediaContainer.matroska;
    }
    if (path.endsWith('.mov')) return MediaContainer.quickTime;
    if (path.endsWith('.webm')) return MediaContainer.webm;
    if (path.endsWith('.avi')) return MediaContainer.avi;
    if (path.endsWith('.ts') || path.endsWith('.m2ts') || path.endsWith('.mts')) {
      return MediaContainer.mpegTs;
    }
    if (path.endsWith('.flv')) return MediaContainer.flv;
    if (path.endsWith('.wmv')) return MediaContainer.wmv;
    if (path.endsWith('.3gp')) return MediaContainer.threeGp;
    return MediaContainer.unknown;
  }

  static bool isHttpMediaUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }

  /// Only standalone files can be saved by the direct-file downloader.
  /// HLS/DASH require a segment-aware offline pipeline and are not treated as
  /// one downloadable file.
  static bool isDirectDownloadable(String rawUrl) {
    if (!isHttpMediaUrl(rawUrl)) return false;
    return switch (containerFor(rawUrl)) {
      MediaContainer.mp4 ||
      MediaContainer.matroska ||
      MediaContainer.quickTime ||
      MediaContainer.webm ||
      MediaContainer.avi ||
      MediaContainer.mpegTs ||
      MediaContainer.flv ||
      MediaContainer.wmv ||
      MediaContainer.threeGp => true,
      MediaContainer.hls || MediaContainer.dash || MediaContainer.unknown => false,
    };
  }

  static String fileExtension(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    final path = uri?.path ?? '';
    final match = RegExp(
      r'\.(mp4|m4v|mkv|mov|webm|avi|ts|m2ts|mts|flv|wmv|3gp)$',
      caseSensitive: false,
    ).firstMatch(path);
    return match?.group(0)?.toLowerCase() ?? '.mp4';
  }

  static String friendlyError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('401') || lower.contains('403') ||
        lower.contains('unauthorized') || lower.contains('forbidden')) {
      return 'The video host denied access. The link may have expired or needs valid authorization.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'This video file could not be found. Try another available stream.';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'The video host took too long to respond. Check your connection or try another stream.';
    }
    if (lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('socketexception') ||
        lower.contains('connection reset')) {
      return 'A network error interrupted playback. Check your internet connection and retry.';
    }
    if (lower.contains('demux') || lower.contains('unsupported format') ||
        lower.contains('unknown format') || lower.contains('codec')) {
      return 'FLIXORA could not read this stream format or codec. Choose another source or quality.';
    }
    if (lower.contains('no playable') || lower.contains('invalid url')) {
      return 'This source does not contain a valid playable video link.';
    }
    return 'Unable to play this video. Please retry or choose another available stream.';
  }
}
