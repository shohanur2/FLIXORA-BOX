import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/downloads/manifest_download_manager.dart';

void main() {
  group('ManifestDownloadManager HLS support', () {
    test('finds quality variants and their external audio playlist', () {
      final options = ManifestDownloadManager.parseHlsOptions(
        Uri.parse('https://cdn.example/master.m3u8'),
        '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",DEFAULT=YES,URI="audio/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1920x1080,AUDIO="aud"
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,AUDIO="aud"
720/index.m3u8
''',
      );

      expect(options, hasLength(2));
      expect(options.first.quality, '1080p');
      expect(
        options.first.url,
        'https://cdn.example/1080/index.m3u8',
      );
      expect(
        options.first.audioUrl,
        'https://cdn.example/audio/en.m3u8',
      );
      expect(options.last.quality, '720p');
    });

    test('recognizes a direct HLS media playlist', () {
      final options = ManifestDownloadManager.parseHlsOptions(
        Uri.parse('https://cdn.example/movie/index.m3u8'),
        '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
segment-1.ts
#EXTINF:6.0,
segment-2.ts
#EXT-X-ENDLIST
''',
      );

      expect(options, hasLength(1));
      expect(options.single.type, 'hls');
      expect(options.single.url, 'https://cdn.example/movie/index.m3u8');
    });
  });

  group('ManifestDownloadManager DASH support', () {
    const staticDash = r'''
<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
     type="static" mediaPresentationDuration="PT10S">
  <Period duration="PT10S">
    <AdaptationSet contentType="video" mimeType="video/mp4">
      <Representation id="video-1" bandwidth="1500000" width="1280" height="720">
        <SegmentTemplate timescale="1" duration="5"
          initialization="init-$RepresentationID$.mp4"
          media="segment-$Number$.m4s" startNumber="1"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';

    test('accepts a static DASH manifest with SegmentTemplate', () {
      expect(
        ManifestDownloadManager.isSupportedDashManifest(staticDash),
        isTrue,
      );
    });

    test('rejects dynamic and DRM-protected DASH manifests', () {
      expect(
        ManifestDownloadManager.isSupportedDashManifest(
          staticDash.replaceFirst('type="static"', 'type="dynamic"'),
        ),
        isFalse,
      );
      expect(
        ManifestDownloadManager.isSupportedDashManifest(
          staticDash.replaceFirst(
            '<Representation',
            '<ContentProtection schemeIdUri="urn:uuid:test"/><Representation',
          ),
        ),
        isFalse,
      );
    });
  });

  test('accepts only safe HTTP(S) manifest URLs', () {
    expect(
      ManifestDownloadManager.safeManifestUri(
        'https://cdn.example/master.m3u8?token=abc',
      ),
      isNotNull,
    );
    expect(
      ManifestDownloadManager.safeManifestUri(
        'https://user:pass@cdn.example/master.m3u8',
      ),
      isNull,
    );
    expect(
      ManifestDownloadManager.safeManifestUri('javascript:alert(1)'),
      isNull,
    );
  });
}
