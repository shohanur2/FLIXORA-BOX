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
    const supportedLanguages = new Set([
      "EN", "BN", "HI", "UR", "AR", "ES", "FR", "DE", "PT", "RU",
      "JA", "KO", "ZH", "TR", "IT", "NL", "PL", "TH", "ID", "MS", "FA",
    ]);
    const requestedLanguages = String(body.languages ?? "EN")
      .split(",")
      .map((value) => value.trim().toUpperCase())
      .filter((value) => supportedLanguages.has(value));
    const languages = [...new Set(requestedLanguages)];
    if (languages.length === 0) languages.push("EN");
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
    if (/^\d{4}$/.test(year)) url.searchParams.set("year", year);
    url.searchParams.set("type", mediaType);
    url.searchParams.set("languages", languages.join(","));
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
    if (payload.status !== true) return json({ error: "No subtitles were found for the requested languages." }, 404);

    const titleResults = Array.isArray(payload.results) ? payload.results as JsonMap[] : [];
    if (tmdbId > 0 && !titleResults.some((item) => Number(item.tmdb_id) === tmdbId)) {
      return json({ error: "No exact TMDB title match was found." }, 404);
    }
    const subtitles = Array.isArray(payload.subtitles) ? payload.subtitles as JsonMap[] : [];
    const candidates: JsonMap[] = [];
    for (const subtitle of subtitles) {
      const unpacked = Array.isArray(subtitle.unpack_files) ? subtitle.unpack_files as JsonMap[] : [];
      for (const file of unpacked) {
        const language = String(file.language ?? "").toUpperCase();
        if (!languages.includes(language)) continue;
        if (mediaType === "tv" &&
            (Number(file.season) !== season || Number(file.episode) !== episode)) continue;
        candidates.push({ ...file, language, release_name: file.release_name ?? subtitle.release_name ?? "" });
      }
    }

    const unique = new Map<string, JsonMap>();
    for (const candidate of candidates) {
      const language = String(candidate.language ?? "").toUpperCase();
      if (!unique.has(language)) unique.set(language, candidate);
    }
    const subtitleResults = [...unique.values()].map((selected) => {
      const rawPath = String(selected.url ?? "");
      const downloadUrl = new URL(rawPath, "https://dl.subdl.com");
      if (downloadUrl.hostname !== "dl.subdl.com" || !downloadUrl.pathname.startsWith("/subtitle/")) {
        throw new Error("Subtitle provider returned an invalid download link.");
      }
      return {
        language: String(selected.language ?? "EN").toLowerCase(),
        format: String(selected.format ?? "srt").toLowerCase(),
        fileName: String(selected.name ?? "subtitle.srt").slice(0, 180),
        releaseName: String(selected.release_name ?? "").slice(0, 180),
        downloadUrl: downloadUrl.toString(),
      };
    });
    if (subtitleResults.length === 0) return json({ error: "No downloadable subtitles were found for the requested languages." }, 404);
    // Keep the previous English-only response fields so already-installed
    // FLIXORA builds continue to work while the updated app is being tested.
    const english = subtitleResults.find((item) => item.language === "en");
    return json({
      subtitles: subtitleResults,
      ...(english ? {
        language: "English",
        format: english.format,
        fileName: english.fileName,
        releaseName: english.releaseName,
        downloadUrl: english.downloadUrl,
      } : {}),
    });
  } catch {
    return json({ error: "Automatic subtitle lookup failed." }, 500);
  }
});
