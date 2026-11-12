import 'package:flutter_test/flutter_test.dart';

import '../lib/streaming/trending_movie_eligibility.dart';

void main() {
  group('TrendingMovieEligibility', () {
    test('recognizes explicit Hindi audio variants, not subtitles', () {
      expect(
        TrendingMovieEligibility.hasHindiAudioVariant([
          'Original · 1080p',
          'Hindi Dub · 720p',
        ]),
        isTrue,
      );
      expect(
        TrendingMovieEligibility.hasHindiAudioVariant([
          'English · 1080p',
          'Hindi Subtitles',
        ]),
        isFalse,
      );
      expect(
        TrendingMovieEligibility.hasHindiAudioVariant([
          'English · 1080p',
          'Original',
        ]),
        isFalse,
      );
    });

    test('classifies Bollywood from Hindi language or regional catalogue', () {
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'hi',
          originCountry: '',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Bollywood',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'ta',
          originCountry: 'India',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Bollywood',
      );
    });

    test('classifies Hollywood from the US catalogue or country metadata', () {
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'en',
          originCountry: '',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: true,
        ),
        'Hollywood',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'en',
          originCountry: 'United States',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Hollywood',
      );
    });

    test('does not guess a regional category from unknown metadata', () {
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'ko',
          originCountry: 'South Korea',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        isEmpty,
      );
    });

    test('keeps recent releases and rejects old or future titles', () {
      final now = DateTime(2026, 11, 12);
      expect(
        TrendingMovieEligibility.isRecentRelease(
          releaseDate: '2025-06-01',
          year: '2025',
          now: now,
        ),
        isTrue,
      );
      expect(
        TrendingMovieEligibility.isRecentRelease(
          releaseDate: '2023-01-01',
          year: '2023',
          now: now,
        ),
        isFalse,
      );
      expect(
        TrendingMovieEligibility.isRecentRelease(
          releaseDate: '2027-01-01',
          year: '2027',
          now: now,
        ),
        isFalse,
      );
    });
  });
}
