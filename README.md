# FLIXORA-BOX
Flixora - Premium Cinematic Movie Streaming Android App

## Android Media3 / FFmpeg fallback

FLIXORA keeps its existing Flutter media_kit player as the primary engine. On Android, failed direct playback can fall back to AndroidX Media3 with the NextLib FFmpeg decoder extension.

- AndroidX Media3 ExoPlayer, HLS and DASH modules: Apache-2.0.
- NextLib Media3 FFmpeg extension: GPL-3.0.
- The pinned NextLib 1.8.0-0.9.0 release adds software decoders for H.264, HEVC, VP8/VP9 and selected audio codecs (including Vorbis, Opus, FLAC, ALAC, MP3, AAC, AC3/EAC3 and TrueHD). AV1 and the newer native bitmap subtitle extensions are not claimed by this pinned release.
- Decoder policy: automatic, hardware/platform decoders first, bundled FFmpeg extension as a format-compatibility fallback. Manual decoder-mode switching is not exposed by this compatible pinned release.
- The fallback is Android-only and is not a guarantee that every protected, DRM, malformed, or unsupported stream will play.

Because this application links the GPL-3.0 NextLib extension, FLIXORA's distributed combined work is licensed under GPL-3.0. Keep the corresponding source and this license available with every distributed APK. The pinned NextLib source is available at https://github.com/anilbeesetti/nextlib/tree/1.8.0-0.9.0.
