import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Media3PlayerController {
  Media3PlayerController({
    required this.onState,
    required this.onError,
  });

  final ValueChanged<Map<String, dynamic>> onState;
  final ValueChanged<String> onError;

  MethodChannel? _methodChannel;
  StreamSubscription<dynamic>? _eventSubscription;

  Future<void> attach(int viewId) async {
    await _eventSubscription?.cancel();
    _methodChannel = MethodChannel('flixora.media3/player/$viewId');

    _eventSubscription = EventChannel('flixora.media3/events/$viewId')
        .receiveBroadcastStream()
        .listen(
      (event) {
        if (event is! Map) return;
        final payload = Map<String, dynamic>.from(event);
        if (payload['event'] == 'error') {
          onError((payload['message'] ?? 'Android Media3 playback failed.')
              .toString());
        } else {
          onState(payload);
        }
      },
      onError: (Object error) {
        onError('Android Media3 connection failed: $error');
      },
    );

    try {
      final state = await _methodChannel!
          .invokeMapMethod<String, dynamic>('getState');
      if (state != null) onState(state);
    } catch (_) {
      // The native view may still be initializing. Its event channel will
      // publish the first state when the player is ready.
    }
  }

  Future<void> _invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final channel = _methodChannel;
    if (channel == null) return;
    await channel.invokeMethod<void>(method, arguments);
  }

  Future<void> play() => _invoke('play');

  Future<void> pause() => _invoke('pause');

  Future<void> seekTo(int positionMs) =>
      _invoke('seekTo', {'positionMs': positionMs});

  Future<void> setResizeMode(String mode) =>
      _invoke('setResizeMode', {'mode': mode});

  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'volume': volume});

  Future<void> setPlaybackSpeed(double speed) =>
      _invoke('setPlaybackSpeed', {'speed': speed});

  Future<void> selectTrack({
    required int trackType,
    required int groupIndex,
    required int trackIndex,
  }) =>
      _invoke('selectTrack', {
        'trackType': trackType,
        'groupIndex': groupIndex,
        'trackIndex': trackIndex,
      });

  Future<void> setMedia({
    required String url,
    required int startPositionMs,
    Map<String, String> headers = const {},
  }) =>
      _invoke('setMedia', {
        'url': url,
        'startPositionMs': startPositionMs,
        'headers': headers,
      });

  Future<void> detach() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _methodChannel = null;
  }

  Future<void> dispose() => detach();
}

class Media3PlayerView extends StatefulWidget {
  const Media3PlayerView({
    super.key,
    required this.url,
    required this.startPositionMs,
    required this.controller,
  });

  final String url;
  final int startPositionMs;
  final Media3PlayerController controller;

  @override
  State<Media3PlayerView> createState() => _Media3PlayerViewState();
}

class _Media3PlayerViewState extends State<Media3PlayerView> {
  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'flixora/media3_player',
      creationParams: {
        'url': widget.url,
        'startPositionMs': widget.startPositionMs,
        'headers': const <String, String>{},
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (viewId) {
        unawaited(widget.controller.attach(viewId));
      },
    );
  }

  @override
  void dispose() {
    unawaited(widget.controller.detach());
    super.dispose();
  }
}
