const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonMap = Record<string, unknown>;

function json(body: JsonMap, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const apiKey = Deno.env.get("SUBDL_API_KEY")?.trim() ?? "";
    if (!apiKey) return json({ error: "Subtitle service is not configured yet." }, 503);

    const body = await request.json() as JsonMap;
    const tmdbId = Number(body.tmdbId ?? 0);
    const title = String(body.title ?? "").trim().slice(0, 180);
    const year = String(body.year ?? "").trim();
    const mediaType = body.mediaType === "tv" ? "tv" : "movie";
    const season = Math.max(0, Math.min(99, Number(body.season ?? 0) || 0));
    const episode = Math.max(0, Math.min(999, Number(body.episode ?? 0) || 0));

    if ((!Number.isInteger(tmdbId) || tmdbId <= 0) && !title) {
      return json({ error: "A valid TMDB ID or title is required." }, 400);
    }
    if (mediaType === "tv" && (!season || !episode)) {
      return json({ error: "Season and episode are required for TV subtitles." }, 400);
    }

    const url = new URL("https://api.subdl.com/api/v1/subtitles");
    url.searchParams.set("api_key", apiKey);
    if (tmdbId > 0) url.searchParams.set("tmdb_id", String(tmdbId));
    else url.searchParams.set("film_name", title);
    if (/^\\d{4}$/.test(year)) url.searchParams.set("year", year);
    url.searchParams.set("type", mediaType);
    url.searchParams.set("languages", "EN");
    url.searchParams.set("subs_per_page", "30");
    url.searchParams.set("unpack", "1");
    url.searchParams.set("client", "custom_integration");
    if (mediaType === "tv") {
      url.searchParams.set("season_number", String(season));
      url.searchParams.set("episode_number", String(episode));
    }

    const response = await fetch(url, { signal: AbortSignal.timeout(12000) });
    if (!response.ok) return json({ error: "Subtitle provider search failed." }, 502);
    const payload = await response.json() as JsonMap;
    if (payload.status !== true) return json({ error: "No English subtitle was found." }, 404);

    const results = Array.isArray(payload.results) ? payload.results as JsonMap[] : [];
    if (tmdbId > 0 && !results.some((item) => Number(item.tmdb_id) === tmdbId)) {
      return json({ error: "No exact TMDB title match was found." }, 404);
    }
    const subtitles = Array.isArray(payload.subtitles) ? payload.subtitles as JsonMap[] : [];
    const candidates: JsonMap[] = [];
    for (const subtitle of subtitles) {
      const unpacked = Array.isArray(subtitle.unpack_files) ? subtitle.unpack_files as JsonMap[] : [];
      for (const file of unpacked) {
        if (String(file.language ?? "").toUpperCase() !== "EN") continue;
        if (mediaType === "tv" &&
            (Number(file.season) !== season || Number(file.episode) !== episode)) continue;
        candidates.push({ ...file, release_name: file.release_name ?? subtitle.release_name ?? "" });
      }
    }

    const selected = candidates.find((item) => item.hi !== true) ?? candidates[0];
    if (!selected) return json({ error: "No downloadable English subtitle file was found." }, 404);

    const rawPath = String(selected.url ?? "");
    const downloadUrl = new URL(rawPath, "https://dl.subdl.com");
    if (downloadUrl.hostname !== "dl.subdl.com" || !downloadUrl.pathname.startsWith("/subtitle/")) {
      return json({ error: "Subtitle provider returned an invalid download link." }, 502);
    }

    return json({
      language: "English",
      format: String(selected.format ?? "srt").toLowerCase(),
      fileName: String(selected.name ?? "English.srt").slice(0, 180),
      releaseName: String(selected.release_name ?? "").slice(0, 180),
      downloadUrl: downloadUrl.toString(),
    });
  } catch {
    return json({ error: "Automatic English subtitle lookup failed." }, 500);
  }
});
