import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/peertube_source_service.dart';

void main() {
  group('PeerTubeSourceService licences and privacy', () {
    test('accepts explicit Public Domain and CC0 labels only', () {
      expect(
        PeerTubeSourceService.isPublicDomainLicense('Public Domain Mark'),
        isTrue,
      );
      expect(
        PeerTubeSourceService.isPublicDomainLicense(
          'Public Domain Dedication CC0',
        ),
        isTrue,
      );
      expect(
        PeerTubeSourceService.isPublicDomainLicense('Attribution'),
        isFalse,
      );
      expect(
        PeerTubeSourceService.isPublicDomainLicense(
          'Attribution - Non Commercial',
        ),
        isFalse,
      );
      expect(
        PeerTubeSourceService.isPublicDomainLicense(
          'Attribution - No Derivatives',
        ),
        isFalse,
      );
      expect(PeerTubeSourceService.isPublicDomainLicense(''), isFalse);
    });

    test('requires public privacy and rejects live or blacklisted items', () {
      expect(
        PeerTubeSourceService.isPublicVideo({
          'privacy': {'id': 1},
          'licence': {'label': 'Public Domain Mark'},
          'isLive': false,
        }),
        isTrue,
      );
      expect(
        PeerTubeSourceService.isPublicVideo({
          'privacy': {'id': 2},
          'licence': {'label': 'Public Domain Mark'},
        }),
        isFalse,
      );
      expect(
        PeerTubeSourceService.isPublicVideo({
          'privacy': {'id': 1},
          'licence': {'label': 'CC0'},
          'isLive': true,
        }),
        isFalse,
      );
      expect(
        PeerTubeSourceService.isPublicVideo({
          'privacy': {'id': 1},
          'licence': {'label': 'CC0'},
          'blacklisted': true,
        }),
        isFalse,
      );
      expect(
        PeerTubeSourceService.isPublicVideo({
          'licence': {'label': 'CC0'},
        }),
        isFalse,
      );
    });
  });

  group('PeerTubeSourceService title matching', () {
    test('matches an exact movie title and rejects a different release year', () {
      expect(
        PeerTubeSourceService.matchesRequestedTitle(
          'Nosferatu (1922)',
          'Nosferatu',
          requestedYear: '1922',
        ),
        isTrue,
      );
      expect(
        PeerTubeSourceService.matchesRequestedTitle(
          'Nosferatu (1922)',
          'Nosferatu',
          requestedYear: '2024',
        ),
        isFalse,
      );
      expect(
        PeerTubeSourceService.matchesRequestedTitle(
          'Nosferatu: A Symphony of Horror',
          'Nosferatu',
        ),
        isFalse,
      );
    });

    test('requires the exact season and episode token for TV results', () {
      expect(
        PeerTubeSourceService.matchesRequestedTitle(
          'Example Series S02E05',
          'Example Series',
          isTv: true,
          season: 2,
          episode: 5,
        ),
        isTrue,
      );
      expect(
        PeerTubeSourceService.matchesRequestedTitle(
          'Example Series S02E06',
          'Example Series',
          isTv: true,
          season: 2,
          episode: 5,
        ),
        isFalse,
      );
      expect(
        PeerTubeSourceService.matchesRequestedTitle(
          'Example Series Season 2 Episode 5',
          'Example Series',
          isTv: true,
          season: 2,
          episode: 5,
        ),
        isTrue,
      );
    });
  });

  group('PeerTubeSourceService safe embed construction', () {
    final validVideo = <String, dynamic>{
      'uuid': '9c9de5e8-0a1e-484a-b099-e80766180a6d',
      'name': 'Nosferatu (1922)',
      'url': 'https://peertube.example/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d',
      'privacy': {'id': 1, 'label': 'Public'},
      'licence': {'id': 8, 'label': 'Public Domain Mark'},
      'isLive': false,
    };

    test('builds the official embed URL on the publishing instance', () {
      final source = PeerTubeSourceService.sourceFromVideo(
        validVideo,
        requestedTitle: 'Nosferatu',
        requestedYear: '1922',
        isTv: false,
      );

      expect(source, isNotNull);
      expect(source!.id, contains('peertube-peertube-example'));
      expect(
        source.url,
        startsWith(
          'https://peertube.example/videos/embed/9c9de5e8-0a1e-484a-b099-e80766180a6d?',
        ),
      );
      expect(source.url, contains('p2p=0'));
      expect(source.loadInIframe, isFalse);
      expect(source.allowedHosts, contains('peertube.example'));
    });

    test('rejects local hosts, IP hosts, and invalid video IDs', () {
      final local = Map<String, dynamic>.from(validVideo)
        ..['url'] = 'https://localhost/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d';
      final ip = Map<String, dynamic>.from(validVideo)
        ..['url'] = 'https://192.168.1.5/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d';
      final badId = Map<String, dynamic>.from(validVideo)..['uuid'] = '../private';

      expect(
        PeerTubeSourceService.sourceFromVideo(
          local,
          requestedTitle: 'Nosferatu',
          requestedYear: '1922',
          isTv: false,
        ),
        isNull,
      );
      expect(
        PeerTubeSourceService.sourceFromVideo(
          ip,
          requestedTitle: 'Nosferatu',
          requestedYear: '1922',
          isTv: false,
        ),
        isNull,
      );
      expect(
        PeerTubeSourceService.sourceFromVideo(
          badId,
          requestedTitle: 'Nosferatu',
          requestedYear: '1922',
          isTv: false,
        ),
        isNull,
      );
    });

    test('rejects videos without explicit public-domain rights', () {
      final unknownLicence = Map<String, dynamic>.from(validVideo)
        ..['licence'] = {'label': 'Attribution'};
      expect(
        PeerTubeSourceService.sourceFromVideo(
          unknownLicence,
          requestedTitle: 'Nosferatu',
          requestedYear: '1922',
          isTv: false,
        ),
        isNull,
      );
    });
  });
}
