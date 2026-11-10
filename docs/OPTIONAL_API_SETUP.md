# Optional FLIXORA catalogue integrations

FLIXORA keeps TMDB, Supabase, the existing Admin panel, and the existing Player as its primary catalogue and playback flow. Optional partner APIs enrich title information; they do not supply playable video streams.

## Included in the app code

- TMDB Watch Providers: platform catalogue and region-filtered discovery (existing FLIXORA OTT tab).
- AniList: exact-title anime matching for the existing anime episode routes.
- OMDb: IMDb rating, Metascore, runtime, content rating and box-office metadata.
- Watchmode: country-specific availability and provider information. It does not return playable streams.
- TasteDive: related movie and TV recommendations.
- Trakt: community rating, vote count and rank.
- Internet Archive: search and playback only for files whose metadata identifies Public Domain or CC0.
- Admin-provided YouTube, Vimeo, Dailymotion and Internet Archive embed/page URLs are handled by the existing in-app player when the provider requirements are met.

## Secure API configuration

Third-party API credentials are **not compiled into the APK**. They are read only by the `external-catalog` Supabase Edge Function.

1. Add these GitHub Actions repository secrets:
   - `SUPABASE_ACCESS_TOKEN`
   - `SUPABASE_PROJECT_REF`
   - Optional `OMDB_API_KEY`
   - Optional `WATCHMODE_API_KEY`
   - Optional `TASTEDIVE_API_KEY`
   - Optional `TRAKT_CLIENT_ID`
2. Open **Actions → Deploy FLIXORA Supabase Functions → Run workflow**.
3. The workflow stores supplied API keys as Supabase Function secrets and deploys `external-catalog`.
4. Rebuild the APK after the function is deployed. If a key is not configured, that provider's panel simply remains empty.

The Supabase project reference is the project identifier in the Supabase project URL (the part before `.supabase.co`). Never put a Supabase service-role key or a third-party secret in Flutter `--dart-define` values.

## Provider requirements / not imported as scrapers

- Dailymotion: all current embeds require a valid Dailymotion Player ID. Without one, the app marks that source unavailable instead of displaying a broken player.
- Simkl: its API rules require Simkl login and watch-history sync when used by a movie/TV/anime tracker. It is not enabled as a metadata-only source; add it after the full PKCE login and incremental sync workflow is implemented.
- HDHub4u, CB Providers scraper scripts, MovieBox private endpoints and the archived 8StreamApi depend on scraping third-party pages, undocumented endpoints or resolver behavior. They are not imported as production sources. Only a documented/authorized source interface should be connected to the FLIXORA Player.
- TMDB, OMDb, Watchmode, TasteDive and Trakt are metadata, discovery, ratings or availability services. They do not replace a licensed video source.

## Playback remains unchanged

Direct Admin MP4/HLS and existing in-app provider routes continue to use FLIXORA's current Player. Metadata/availability integrations never override the Admin source, publication status, or season/episode selection.
