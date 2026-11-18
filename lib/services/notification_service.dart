import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FlixoraNotificationService {
  FlixoraNotificationService._();

  static const String _preferenceKey = 'flixora_notifications';
  static const String _channelId = 'flixora_downloads';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _enabled = true;

  static Future<void> initialize() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'FLIXORA Downloads',
        description: 'Notifications when video downloads finish.',
        importance: Importance.high,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_preferenceKey) ?? true;
    _initialized = true;

    if (_enabled) {
      await android?.requestNotificationsPermission();
    }
  }

  static Future<bool> enable() async {
    try {
      if (!_initialized) await initialize();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.requestNotificationsPermission() ?? true;
      _enabled = allowed;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, allowed);
      return allowed;
    } catch (_) {
      _enabled = false;
      return false;
    }
  }

  static Future<void> disable() async {
    _enabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferenceKey, false);
  }

  static Future<void> showDownloadComplete({
    required String title,
    required int uniqueId,
  }) async {
    try {
      if (!_initialized) await initialize();
      if (!_enabled || title.trim().isEmpty) return;

      await _plugin.show(
        0x40000000 | (uniqueId & 0x3fffffff),
        'Download Complete',
        '${title.trim()} has been downloaded successfully.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'FLIXORA Downloads',
            channelDescription: 'Notifications when video downloads finish.',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (_) {
      // Notification failures must never interrupt downloads or playback.
    }
  }
}
