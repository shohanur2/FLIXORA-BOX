import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FLIXORA's fail-open interstitial gate for online video playback.
///
/// Downloaded playback never calls this service. Ads are shown at most once
/// per 24 hours after the SDK confirms that an interstitial was displayed.
class AdMobService {
  AdMobService._();

  static const String _adUnitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_AD_UNIT_ID',
    // Google's official Android interstitial test unit. Replace through
    // --dart-define only after FLIXORA is ready for production ads.
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  static const String _lastShownKey =
      'flixora_admob_last_interstitial_shown_at_ms';
  static const Duration _cooldown = Duration(hours: 24);
  static const Duration _loadTimeout = Duration(seconds: 8);

  static Future<void>? _initialization;
  static Future<void>? _activeShow;
  static int? _lastShownAtMs;
  static bool _initialized = false;

  static Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint('FLIXORA AdMob SDK initialized.');
    } catch (error) {
      debugPrint('FLIXORA AdMob initialization failed: $error');
    }
  }

  /// Waits for an interstitial only when the 24-hour window has elapsed.
  /// Any SDK/load/show failure resolves immediately so playback can proceed.
  static Future<void> showBeforeOnlinePlayback() async {
    final active = _activeShow;
    if (active != null) {
      await active;
      return;
    }

    final operation = _showIfDue();
    _activeShow = operation;
    try {
      await operation;
    } catch (error) {
      debugPrint('FLIXORA AdMob gate failed open: $error');
    } finally {
      if (identical(_activeShow, operation)) _activeShow = null;
    }
  }

  static Future<void> _showIfDue() async {
    try {
      if (!_initialized) await initialize();
      if (!_initialized) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      var lastShown = _lastShownAtMs;
      try {
        final preferences = await SharedPreferences.getInstance();
        lastShown ??= preferences.getInt(_lastShownKey);
      } catch (error) {
        debugPrint('Could not read FLIXORA ad cooldown: $error');
      }

      if (lastShown != null && now - lastShown < _cooldown.inMilliseconds) {
        return;
      }

      final ad = await _loadInterstitial();
      if (ad == null) return;

      final completed = Completer<void>();
      var disposed = false;

      void disposeAd() {
        if (disposed) return;
        disposed = true;
        ad.dispose();
      }

      void finish() {
        disposeAd();
        if (!completed.isCompleted) completed.complete();
      }

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdShowedFullScreenContent: (shownAd) {
          final shownAt = DateTime.now().millisecondsSinceEpoch;
          _lastShownAtMs = shownAt;
          unawaited(_persistShownAt(shownAt));
          debugPrint('FLIXORA interstitial displayed.');
        },
        onAdDismissedFullScreenContent: (dismissedAd) {
          debugPrint('FLIXORA interstitial dismissed.');
          finish();
        },
        onAdFailedToShowFullScreenContent: (failedAd, error) {
          debugPrint('FLIXORA interstitial show failed: $error');
          finish();
        },
      );

      try {
        await ad.show();
      } catch (error) {
        debugPrint('FLIXORA interstitial show exception: $error');
        finish();
      }

      // The SDK's dismiss/failure callback completes this future. The show()
      // method itself may return before the full-screen ad is dismissed.
      await completed.future;
    } catch (error) {
      debugPrint('FLIXORA AdMob unavailable; continuing playback: $error');
    }
  }

  static Future<InterstitialAd?> _loadInterstitial() async {
    final completer = Completer<InterstitialAd?>();
    var timedOut = false;

    try {
      InterstitialAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (timedOut) {
              ad.dispose();
            } else if (!completer.isCompleted) {
              completer.complete(ad);
            } else {
              ad.dispose();
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint('FLIXORA interstitial load failed: $error');
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );

      return await completer.future.timeout(
        _loadTimeout,
        onTimeout: () {
          timedOut = true;
          debugPrint('FLIXORA interstitial load timed out; continuing video.');
          return null;
        },
      );
    } catch (error) {
      timedOut = true;
      debugPrint('FLIXORA interstitial request failed: $error');
      return null;
    }
  }

  static Future<void> _persistShownAt(int timestamp) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_lastShownKey, timestamp);
    } catch (error) {
      debugPrint('Could not save FLIXORA ad cooldown: $error');
    }
  }
}
