import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/ott_catalog_service.dart';

void main() {
  group('OttProvider', () {
    test('parses provider logo and display information from TMDB', () {
      final provider = OttProvider.fromJson({
        'provider_id': 8,
        'provider_name': 'Netflix',
        'logo_path': '/netflix-logo.png',
        'display_priority': 1,
      });

      expect(provider.id, 8);
      expect(provider.name, 'Netflix');
      expect(provider.logoUrl, 'https://image.tmdb.org/t/p/w185/netflix-logo.png');
    });

    test('sorts featured platforms first and removes duplicate providers', () {
      final sorted = OttCatalogService.sortProviders([
        const OttProvider(id: 15, name: 'Hulu', logoPath: '', displayPriority: 1),
        const OttProvider(id: 8, name: 'Netflix', logoPath: '', displayPriority: 9),
        const OttProvider(id: 9, name: 'Prime Video', logoPath: '', displayPriority: 4),
        const OttProvider(id: 8, name: 'Netflix duplicate', logoPath: '', displayPriority: 2),
      ]);

      expect(sorted.map((provider) => provider.id), [8, 9, 15]);
      expect(sorted.first.name, 'Netflix');
    });
  });
}
