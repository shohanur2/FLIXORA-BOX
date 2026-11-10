# FLIXORA Authorized Provider Integration

FLIXORA keeps its existing playback priority:

1. Admin-managed direct MP4/HLS sources and recognized Admin embeds
2. Authorized provider results discovered for the selected title and (for TV) exact season/episode
3. Existing built-in provider routes as fallbacks

## Integrated provider discovery

The visitor player can query these sources in parallel:

- **Dramachi** — public JSON catalogue/title/episode interfaces and the CDN URL returned by its normal API response.
- **CircleFTP (BDIX)** — post search/details API; a direct media URL is accepted only from the configured CircleFTP host.
- **4KHDHub** — public search/detail pages plus the supported HubCloud/HubDrive public resolver flow. Resolver output is restricted to HTTPS media URLs and known direct-file CDN endpoints; local/private IPs, login/logout pages, archives, and unknown redirect pages are rejected.

Provider results are title/year matched, deduplicated, and added after a recognized Admin embed source. TV results must match the selected season and episode. Direct media links play through FLIXORA's native `media_kit` player; playback errors move to the next provider. Existing embedded players continue to use the WebView player.

## Build-time endpoint configuration

The following GitHub Actions secrets can override the defaults at build time:

| Secret | Default |
| --- | --- |
| `FLIXORA_DRAMACHI_API_BASE_URL` | `https://api.nodeobjects.com/` |
| `FLIXORA_CIRCLEFTP_API_BASE_URL` | `http://new.circleftp.net:5000/api` |
| `FLIXORA_4KHDHUB_BASE_URL` | `https://4khdhub.one/` |

If a custom BDIX host is used, its exact hostname must also be added to the Android network-security allowlist in `android/app/src/main/res/xml/network_security_config.xml`.

CircleFTP currently uses HTTP. Android cleartext traffic is restricted to `new.circleftp.net` in `network_security_config.xml`; other hosts remain blocked by default. If an authorized BDIX operator provides a different server hostname, update that hostname in the network security allowlist before building.

## Limits and verification

- Discovery is best-effort and times out; a provider can return no result when unavailable or when a title/episode is not in its catalogue.
- A URL being discovered does not prove that it will play on every device or network. Test actual playback on-device.
- This integration does not bypass login, subscription/VIP controls, DRM, or other access controls.
- 4KHDHub mirror support is best-effort. Some hosts may expire links, require unsupported headers, or reject in-app playback; those sources are skipped or moved to the next provider.
- Provider access permission and rights to stream or redistribute the underlying media are separate matters; use only sources cleared for FLIXORA playback.
