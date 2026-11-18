# FLIXORA Subtitle Extensions

GitHub is the source of truth for FLIXORA subtitle add-on discovery and registry updates. This repository is independent of the FLIXORA Admin Panel.

## Registry

- Registry: `registry.json`
- Protocol target: Stremio Add-on Protocol, subtitle resource only
- Manifest: `{baseUrl}/manifest.json`
- Subtitle endpoint: `{baseUrl}/subtitles/{type}/{id}.json`
- Expected response: `{ "subtitles": [{ "id": "...", "url": "https://...", "lang": "en", "label": "..." }] }`

Only verified HTTPS add-on manifest URLs should be listed. The registry starts empty; no unverified or invented add-on endpoint is enabled by default.

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

The example is documentation only, not an installable add-on.

## Runtime and safety contract

- FLIXORA fetches this registry from GitHub and validates entries and manifests.
- Require HTTPS for registry, manifest, and subtitle URLs.
- Accept only add-ons that declare the subtitle resource and supported movie/series types.
- Ignore catalog, stream, meta, player, library, and other capabilities.
- Send only the media identifier and minimum episode context needed by the subtitle protocol.
- Never send account data, playback history, or unrelated personal information to add-ons.
- Treat add-on metadata and subtitle payloads as untrusted input.
- Validate downloaded subtitle content and formats before passing it to FLIXORA's existing subtitle loader.
- An add-on failure must not stop other enabled add-ons.
- Do not download or execute arbitrary Dart, JavaScript, Python, or native code from GitHub.
- Keep the existing Subtitle Panel appearance and every non-subtitle feature unchanged.

## Protocol references

- [Stremio Add-on Protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md)
- [Stremio subtitle response](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/subtitles.md)
