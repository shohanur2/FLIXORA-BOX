import 'download_manager.dart';
import '../streaming/provider_catalog.dart';

/// Explains whether the currently selected embed provider exposes a supported
/// downloadable media source. This deliberately does not inspect or extract
/// media URLs from provider-owned web pages.
class ProviderDownloadAdapter {
  ProviderDownloadAdapter._();

  /// Uses only a provider source that FLIXORA's provider catalog explicitly
  /// marks as direct media. Embed pages and header-protected sources are not
  /// extracted or reverse-engineered.
  static Future<List<Map<String, String>>> inspectDirectSource(
    ProviderEmbedSource? source,
  ) async {
    if (source == null ||
        !source.isDirectMedia ||
        source.url.isEmpty ||
        source.httpHeaders.isNotEmpty) {
      return const [];
    }
    return DownloadManager.inspectDownloadSources(
      source.url,
      qualityLabel: source.languageLabel ?? source.name,
    );
  }

  static String? unavailableReason(String? providerId) {
    final id = (providerId ?? '').trim().toLowerCase();
    if (id.startsWith('vidrift')) {
      return 'VidRift is connected as an embed player. Its documented integration does not expose a direct download API.';
    }
    if (id.startsWith('play4u')) {
      return 'Play4U is currently connected through an embed route only. FLIXORA has no official downloadable source configured for this episode.';
    }
    if (id.isEmpty) {
      return 'No episode-specific download source is available. Add a direct MP4/MKV file or a clear HLS/DASH VOD source for this episode in Admin.';
    }
    return 'This provider has not supplied an official downloadable media URL for this episode.';
  }
}
