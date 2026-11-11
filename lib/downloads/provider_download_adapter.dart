/// Explains whether the currently selected embed provider exposes a supported
/// downloadable media source. This deliberately does not inspect or extract
/// media URLs from provider-owned web pages.
class ProviderDownloadAdapter {
  ProviderDownloadAdapter._();

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
