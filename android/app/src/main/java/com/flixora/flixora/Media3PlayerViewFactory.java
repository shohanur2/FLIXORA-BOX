package com.flixora.flixora;

import android.content.Context;

import java.util.Collections;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public final class Media3PlayerViewFactory extends PlatformViewFactory {
    private final BinaryMessenger messenger;

    public Media3PlayerViewFactory(BinaryMessenger messenger) {
        super(StandardMessageCodec.INSTANCE);
        this.messenger = messenger;
    }

    @Override
    public PlatformView create(Context context, int viewId, Object args) {
        Map<String, Object> params;
        if (args instanceof Map) {
            params = (Map<String, Object>) args;
        } else {
            params = Collections.emptyMap();
        }
        return new Media3PlayerPlatformView(context, viewId, messenger, params);
    }
}
