# FLIXORA Provider, Player and Frontend Integration

FLIXORA keeps catalogue information, provider availability and playable media sources separate.

## Playback source order

1. Admin-managed direct MP4/HLS/DASH source, or an Admin-curated official embed.
2. Verified Public Domain / CC0 discoveries from PeerTube and Internet Archive.
3. The existing configured fallback embed routes.

The Player keeps its existing native media_kit engine, Android Media3 fallback and WebView embed surface. Direct media continues through the native player; official provider embeds open in the in-app WebView. A source failure can move playback to the next available configured source.

## Public-domain discovery

- **PeerTube / Sepia Search** — searches public PeerTube instances. FLIXORA accepts only public videos explicitly labelled Public Domain or CC0. Movie title/year matching is applied; TV results must match the selected season and episode token exactly. Results use the publishing instance's official PeerTube embed player.
- **Internet Archive** — movie-only discovery. FLIXORA checks the Archive item's rights metadata and requires a public supported video file before adding its official Archive embed. Unknown, restricted, or copyrighted uploads are not automatically treated as public-domain content. TV episodes are not searched by this integration.

Discovery runs in the background with a short initial wait so a slow public catalogue does not hold up normal playback. Late verified results are added to the fallback list without interrupting a stream that is already playing. Discovery is skipped while the device is offline.

## Official embeds

- **YouTube** — Admin-provided YouTube watch, short, or embed URLs are normalized to YouTube's official privacy-enhanced embed player.
- **Vimeo** — Admin-provided Vimeo video URLs are normalized to the official Vimeo player.
- **Internet Archive** — Admin-curated Archive embed URLs are supported; discovered Archive results additionally pass the public-domain rights and file checks above.

FLIXORA does not scrape YouTube/Vimeo pages or extract protected media URLs. Add only official embeds that the uploader or rights holder has authorized for use.

## Metadata and availability

- **TMDB / AniList** — catalogue metadata, title IDs, season/episode information and anime matching.
- **OMDb** — ratings, Metascore, runtime, content rating and other title metadata.
- **Watchmode** — country-specific streaming availability, format and provider links. Its results are informational and do not provide playback streams; provider links open the provider's website.
- **Trakt** — community ratings and ranking information. Use only when FLIXORA's content and playback integrations comply with Trakt's API policy.

The optional OMDb, Watchmode and Trakt credentials are stored as Supabase Edge Function secrets, not inside the APK. See [OPTIONAL_API_SETUP.md](OPTIONAL_API_SETUP.md).

## Limits and verification

- A catalogue match or provider availability result is not proof that a video is playable.
- Public-domain filtering is intentionally conservative. A title may have no result even when a copy exists, because the licence or exact episode cannot be verified.
- Embed providers may block in-app playback, require user interaction, or be region-restricted.
- Existing Admin source priority, selected TV season/episode, offline Home cache and no-internet screen must remain unchanged.
- Do not bypass login, subscription/VIP controls, DRM, or other access restrictions. Provider access and rights to stream or redistribute the underlying media are separate matters.
