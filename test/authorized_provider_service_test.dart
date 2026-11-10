import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/authorized_provider_service.dart';
import 'package:flixora/streaming/provider_catalog.dart';

void main() {
  group('AuthorizedProviderService', () {
    test('returns no results for a blank title without making requests', () async {
      final sources = await AuthorizedProviderService.discover(
        title: '   ',
        isTv: false,
      );

      expect(sources, isEmpty);
    });
  });

  group('ProviderEmbedSource direct media', () {
    test('embed sources default to WebView mode', () {
      const source = ProviderEmbedSource(
        id: 'test-embed',
        name: 'Test Embed',
        url: 'https://example.com/embed/1',
        allowedHosts: <String>{'example.com'},
      );

      expect(source.isDirectMedia, isFalse);
      expect(source.isAvailable, isTrue);
    });

    test('direct media sources can opt into native playback', () {
      const source = ProviderEmbedSource(
        id: 'test-direct',
        name: 'Test Direct',
        url: 'https://cdn.example.com/movie.mp4',
        allowedHosts: <String>{'cdn.example.com'},
        isDirectMedia: true,
      );

      expect(source.isDirectMedia, isTrue);
      expect(source.isAvailable, isTrue);
      expect(source.httpHeaders, isEmpty);
    });
  });
}
