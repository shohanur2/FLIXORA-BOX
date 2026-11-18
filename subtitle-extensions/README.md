# FLIXORA Subtitle Extensions

GitHub is the source of truth for FLIXORA subtitle add-on discovery and registry updates. This repository is independent of the FLIXORA Admin Panel.

## Enabled add-ons

The registry currently includes:
- **OpenSubtitles v3** — official Stremio subtitle add-on manifest: `https://opensubtitles-v3.strem.io/manifest.json`
- **Subtitle Search Engine** — public Stremio add-on manifest: `https://subtitles.website/stremio/manifest.json`

Both are queried for English and Bengali subtitle results. Availability depends on each add-on's catalogue, language coverage, uptime, and rate limits. The public Subtitle Search Engine service documents a guest limit of 10 requests per day; HTTP 429 responses are treated as an add-on failure and FLIXORA continues to the next enabled extension.

## Protocol

- Registry: `registry.json`
- Protocol: Stremio Add-on Protocol, subtitle resource only
- Manifest: the configured public HTTPS manifest URL
- Subtitle endpoint: `/subtitles/{type}/{id}.json`
- Movie ID: IMDb ID, e.g. `tt0133093`
- Series episode ID: IMDb ID plus season and episode, e.g. `tt0944947:1:1`
- Expected response: `{ "subtitles": [{ "id": "...", "url": "https://...", "lang": "en", "label": "..." }] }`

## Registry entry

```json
{
  "id": "unique.addon.id",
  "name": "Human readable name",
  "manifestUrl": "https://verified-addon.example/manifest.json",
  "enabled": true,
  "priority": 100,
  "languages": ["en", "bn"],
  "types": ["movie", "series"]
}
```

## Runtime and safety contract

- FLIXORA fetches this registry from GitHub and validates entries and manifests.
- Require HTTPS for registry, manifest, and subtitle URLs.
- Accept only add-ons that declare the subtitle resource and supported movie/series types.
- Ignore catalog, stream, meta, player, library, and other capabilities.
- Send only the IMDb media identifier and minimum episode context needed by the subtitle protocol.
- Never send account data, playback history, or unrelated personal information to add-ons.
- Treat add-on metadata and subtitle payloads as untrusted input.
- Validate downloaded subtitle content and formats before passing it to FLIXORA's existing subtitle loader.
- An add-on failure must not stop other enabled add-ons.
- Do not download or execute arbitrary Dart, JavaScript, Python, or native code from GitHub.
- Keep manual subtitle import and embedded subtitle selection available.
- Keep the existing Subtitle Panel appearance and every non-subtitle feature unchanged.

## Protocol references

- [Stremio Add-on Protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md)
- [Stremio subtitle response](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/subtitles.md)
