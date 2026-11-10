package com.flixora.flixora;

import android.content.Context;
import android.graphics.Color;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.PlayerView;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.DecoderManager;
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.DecoderMode;
import io.github.anilbeesetti.nextlib.media3ext.ffdecoder.NextRenderersFactory;

@UnstableApi
final class Media3PlayerPlatformView implements PlatformView,
        MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private final PlayerView playerView;
    private final ExoPlayer player;
    private final DecoderManager decoderManager;
    private final DefaultHttpDataSource.Factory httpDataSourceFactory;
    private final MethodChannel methodChannel;
    private final EventChannel eventChannel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private EventChannel.EventSink eventSink;
    private Map<String, Object> lastError;
    private boolean disposed = false;

    private final Runnable stateTicker = new Runnable() {
        @Override
        public void run() {
            if (disposed) return;
            emitState();
            mainHandler.postDelayed(this, 500);
        }
    };

    Media3PlayerPlatformView(
            Context context,
            int viewId,
            BinaryMessenger messenger,
            Map<String, Object> creationParams) {

        methodChannel = new MethodChannel(messenger, "flixora.media3/player/" + viewId);
        eventChannel = new EventChannel(messenger, "flixora.media3/events/" + viewId);
        methodChannel.setMethodCallHandler(this);
        eventChannel.setStreamHandler(this);

        httpDataSourceFactory = new DefaultHttpDataSource.Factory()
                .setUserAgent("FLIXORA Android Media3")
                .setAllowCrossProtocolRedirects(true);

        applyRequestHeaders(creationParams.get("headers"));

        DefaultTrackSelector trackSelector = new DefaultTrackSelector(context);
        decoderManager = new DecoderManager(DecoderMode.AUTO, DecoderMode.AUTO);

        NextRenderersFactory renderersFactory =
                new NextRenderersFactory(context).setDecoderManager(decoderManager);

        DefaultDataSource.Factory dataSourceFactory =
                new DefaultDataSource.Factory(context, httpDataSourceFactory);

        DefaultMediaSourceFactory mediaSourceFactory =
                new DefaultMediaSourceFactory(dataSourceFactory);

        player = new ExoPlayer.Builder(context)
                .setTrackSelector(trackSelector)
                .setRenderersFactory(renderersFactory)
                .setMediaSourceFactory(mediaSourceFactory)
                .build();

        decoderManager.attach(player);

        playerView = new PlayerView(context);
        playerView.setBackgroundColor(Color.BLACK);
        playerView.setShutterBackgroundColor(Color.BLACK);
        playerView.setPlayer(player);
        playerView.setUseController(true);
        playerView.setControllerAutoShow(true);
        playerView.setControllerHideOnTouch(true);
        playerView.setControllerShowTimeoutMs(5000);
        playerView.setKeepContentOnPlayerReset(true);
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING);
        playerView.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_FIT);
        playerView.setUseArtwork(false);

        player.addListener(new Player.Listener() {
            @Override
            public void onPlaybackStateChanged(int playbackState) {
                emitState();
            }

            @Override
            public void onIsPlayingChanged(boolean isPlaying) {
                emitState();
            }

            @Override
            public void onPlayerError(@NonNull PlaybackException error) {
                Map<String, Object> payload = new HashMap<>();
                payload.put("event", "error");
                payload.put("message", error.getMessage() == null
                        ? "Android Media3 could not play this stream."
                        : error.getMessage());
                payload.put("errorCode", error.errorCode);
                lastError = payload;
                sendEvent(payload);
            }
        });

        String initialUrl = stringValue(creationParams.get("url"));
        long startPositionMs = longValue(creationParams.get("startPositionMs"), 0L);
        if (!initialUrl.isEmpty()) {
            player.setMediaItem(buildMediaItem(initialUrl,
                    stringValue(creationParams.get("mimeType"))), Math.max(0L, startPositionMs));
            player.prepare();
            player.play();
        }

        mainHandler.post(stateTicker);
    }

    @NonNull
    @Override
    public View getView() {
        return playerView;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (disposed) {
            result.error("PLAYER_DISPOSED", "The Media3 player has been disposed.", null);
            return;
        }

        try {
            switch (call.method) {
                case "getState":
                    result.success(createState());
                    break;
                case "play":
                    player.play();
                    result.success(null);
                    break;
                case "pause":
                    player.pause();
                    result.success(null);
                    break;
                case "seekTo":
                    player.seekTo(longValue(call.argument("positionMs"), 0L));
                    result.success(null);
                    break;
                case "setVolume":
                    Number volume = call.argument("volume");
                    player.setVolume(volume == null ? 1f : Math.max(0f, Math.min(1f, volume.floatValue())));
                    result.success(null);
                    break;
                case "setPlaybackSpeed":
                    Number speed = call.argument("speed");
                    player.setPlaybackSpeed(speed == null ? 1f : Math.max(0.25f, Math.min(3f, speed.floatValue())));
                    result.success(null);
                    break;
                case "setResizeMode":
                    String resizeMode = stringValue(call.argument("mode"));
                    playerView.setResizeMode("ZOOM".equalsIgnoreCase(resizeMode)
                            ? AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                            : AspectRatioFrameLayout.RESIZE_MODE_FIT);
                    result.success(null);
                    break;
                case "setVideoDecoder":
                    decoderManager.selectVideoDecoder(parseDecoderMode(call.argument("mode")));
                    result.success(null);
                    break;
                case "setAudioDecoder":
                    decoderManager.selectAudioDecoder(parseDecoderMode(call.argument("mode")));
                    result.success(null);
                    break;
                case "setMedia":
                    String url = stringValue(call.argument("url"));
                    if (url.isEmpty()) {
                        result.error("INVALID_MEDIA", "A valid media URL is required.", null);
                        break;
                    }
                    applyRequestHeaders(call.argument("headers"));
                    long positionMs = longValue(call.argument("startPositionMs"), 0L);
                    String mimeType = stringValue(call.argument("mimeType"));
                    player.setMediaItem(buildMediaItem(url, mimeType), Math.max(0L, positionMs));
                    player.prepare();
                    player.play();
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception error) {
            result.error("MEDIA3_COMMAND_FAILED",
                    error.getMessage() == null ? "Media3 command failed." : error.getMessage(),
                    null);
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
        emitState();
        if (lastError != null) sendEvent(lastError);
    }

    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }

    private MediaItem buildMediaItem(String rawUrl, String requestedMimeType) {
        Uri uri = Uri.parse(rawUrl);
        String mimeType = requestedMimeType;
        if (mimeType == null || mimeType.isEmpty()) {
            String path = uri.getPath() == null ? "" : uri.getPath().toLowerCase();
            if (path.endsWith(".m3u8")) {
                mimeType = MimeTypes.APPLICATION_M3U8;
            } else if (path.endsWith(".mpd")) {
                mimeType = MimeTypes.APPLICATION_MPD;
            }
        }

        MediaItem.Builder builder = new MediaItem.Builder().setUri(uri);
        if (mimeType != null && !mimeType.isEmpty()) {
            builder.setMimeType(mimeType);
        }
        return builder.build();
    }

    private void applyRequestHeaders(Object rawHeaders) {
        Map<String, String> headers = new HashMap<>();
        if (rawHeaders instanceof Map) {
            Map<?, ?> source = (Map<?, ?>) rawHeaders;
            for (Map.Entry<?, ?> entry : source.entrySet()) {
                if (entry.getKey() != null && entry.getValue() != null) {
                    headers.put(entry.getKey().toString(), entry.getValue().toString());
                }
            }
        }
        httpDataSourceFactory.setDefaultRequestProperties(headers);
    }

    private DecoderMode parseDecoderMode(Object value) {
        String mode = stringValue(value).toUpperCase();
        if (mode.isEmpty()) mode = "AUTO";
        return DecoderMode.valueOf(mode);
    }

    private Map<String, Object> createState() {
        Map<String, Object> state = new HashMap<>();
        long duration = player.getDuration();
        state.put("event", "state");
        state.put("positionMs", Math.max(0L, player.getCurrentPosition()));
        state.put("durationMs", duration == C.TIME_UNSET ? 0L : Math.max(0L, duration));
        state.put("isPlaying", player.isPlaying());
        state.put("isBuffering", player.getPlaybackState() == Player.STATE_BUFFERING);
        state.put("isReady", player.getPlaybackState() == Player.STATE_READY);
        state.put("playbackState", player.getPlaybackState());
        state.put("videoDecoderMode", decoderManager.getVideoMode().name());
        state.put("audioDecoderMode", decoderManager.getAudioMode().name());
        DecoderMode activeVideo = decoderManager.getActiveVideoMode();
        DecoderMode activeAudio = decoderManager.getActiveAudioMode();
        state.put("activeVideoDecoderMode", activeVideo == null ? "" : activeVideo.name());
        state.put("activeAudioDecoderMode", activeAudio == null ? "" : activeAudio.name());
        return state;
    }

    private void emitState() {
        sendEvent(createState());
    }

    private void sendEvent(Map<String, Object> payload) {
        if (eventSink != null && !disposed) {
            eventSink.success(payload);
        }
    }

    private static String stringValue(Object value) {
        return value == null ? "" : value.toString().trim();
    }

    private static long longValue(Object value, long fallback) {
        return value instanceof Number ? ((Number) value).longValue() : fallback;
    }

    @Override
    public void dispose() {
        if (disposed) return;
        disposed = true;
        mainHandler.removeCallbacks(stateTicker);
        eventSink = null;
        methodChannel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
        playerView.setPlayer(null);
        decoderManager.detach();
        player.release();
    }
}
