# FLIXORA offline download support

All content categories share the same download manager:

- Movies: title-level direct sources or clear VOD manifests.
- TV Shows, Web Series, Drama and Anime: select a season and episode in the player, then download that episode's configured source and quality.

## Supported sources

- Direct MP4, M4V, MKV, WebM, MOV and AVI files.
- Finite, clear HLS VOD playlists (`.m3u8`) including master-playlist quality variants and a default external audio rendition.
- Static, unprotected DASH manifests (`.mpd`) using supported SegmentTemplate or SegmentList layouts.

The manager supports pause, resume, cancel, partial-segment restoration after app restart, app-private storage, and offline playback through the FLIXORA player.

## Episode source setup

Episode-specific URLs are read from `public.movie_episode_video_qualities`. The additive
migration and Admin editor are included in the FLIXORA-ADMIN episode-download-source
change:

`supabase/migrations/20261111210000_episode_video_download_sources.sql`

In FLIXORA-ADMIN, edit a TV title and add a source for each season/episode/quality.
Use an authorized direct media URL, not an embed page.

## Deliberate limitations

- HLS live playlists, byte-range segments, encrypted HLS keys and DRM are rejected.
- DASH dynamic manifests, DRM, multiple periods, byte-range segments and SegmentBase layouts are rejected.
- Play4U and VidRift currently provide embed-player routes in FLIXORA. Their embed pages are not downloadable files. The app does not scrape hidden player URLs or bypass DRM, login, captcha, hotlink controls or provider restrictions.
- A provider can be used for downloads only when it supplies an official, permitted direct file or clear VOD manifest URL.
- Downloads continue while navigating inside the app. Android may pause work if the app is force-stopped or the OS terminates it; completed segments are retained for resume.
