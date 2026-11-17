const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
type JsonMap = Record<string, unknown>;
type SearchArgs = {
  apiKey: string; tmdbId: number; title: string; year: string;
  mediaType: string; languages: string[]; season: number; episode: number;
  providerErrors: string[];
};
function json(body: JsonMap, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}
const supportedLanguages = new Set(["EN","BN","HI","UR","AR","ES","FR","DE","PT","RU","JA","KO","ZH","TR","IT","NL","PL","TH","ID","MS","FA"]);
function languageCode(value: unknown): string {
  const code = String(value ?? "").trim().toUpperCase();
  const aliases: Record<string,string> = {
    BN:"bn",BEN:"bn",BENGALI:"bn",BANGLA:"bn",EN:"en",ENG:"en",ENGLISH:"en",
    HI:"hi",HIN:"hi",HINDI:"hi",UR:"ur",URD:"ur",URDU:"ur",ARA:"ar",AR:"ar",
    ES:"es",SPA:"es",FR:"fr",FRE:"fr",FRA:"fr",DE:"de",GER:"de",DEU:"de",
    PT:"pt",POR:"pt",RU:"ru",RUS:"ru",JA:"ja",JPN:"ja",KO:"ko",KOR:"ko",
    ZH:"zh",CHI:"zh",ZHO:"zh",TR:"tr",TUR:"tr",IT:"it",ITA:"it",NL:"nl",
    NLD:"nl",PL:"pl",POL:"pl",TH:"th",THA:"th",ID:"id",IND:"id",
    MS:"ms",MAY:"ms",MSA:"ms",FA:"fa",PER:"fa",FAS:"fa"
  };
  return aliases[code] ?? code.toLowerCase();
}
function safeDownloadUrl(raw: unknown, allowedHost: string): string | null {
  try {
    const value = new URL(String(raw ?? ""));
    if (value.protocol !== "https:" ||
        !(value.hostname === allowedHost || value.hostname.endsWith("." + allowedHost))) return null;
    return value.toString();
  } catch { return null; }
}
function releaseKey(item: JsonMap): string {
  return [item.language, item.releaseName, item.fileName, item.downloadUrl]
    .map(v => String(v ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim())
    .join("|");
}
function capAndDedupe(items: JsonMap[]): JsonMap[] {
  const seen = new Set<string>();
  const perLanguage = new Map<string, number>();
  const output: JsonMap[] = [];
  for (const item of items) {
    const lang = String(item.language ?? "").toLowerCase();
    const key = releaseKey(item);
    const count = perLanguage.get(lang) ?? 0;
    if (!lang || seen.has(key) || count >= 5) continue;
    seen.add(key);
    perLanguage.set(lang, count + 1);
    output.push(item);
    if (output.length >= 70) break;
  }
  return output;
}
async function searchSubDL(args: SearchArgs, titleFallback = false, omitYear = false): Promise<JsonMap[]> {
  const url = new URL("https://api.subdl.com/api/v1/subtitles");
  url.searchParams.set("api_key", args.apiKey);
  if (!titleFallback && args.tmdbId > 0) url.searchParams.set("tmdb_id", String(args.tmdbId));
  else url.searchParams.set("film_name", args.title);
  if (!omitYear && /^\d{4}$/.test(args.year)) url.searchParams.set("year", args.year);
  url.searchParams.set("type", args.mediaType);
  url.searchParams.set("languages", args.languages.join(","));
  url.searchParams.set("subs_per_page", "30");
  url.searchParams.set("unpack", "1");
  url.searchParams.set("client", "custom_integration");
  if (args.mediaType === "tv") {
    url.searchParams.set("season_number", String(args.season));
    url.searchParams.set("episode_number", String(args.episode));
  }
  const response = await fetch(url, { signal: AbortSignal.timeout(9000) });
  if (!response.ok) {
    args.providerErrors.push(`SubDL search HTTP ${response.status}`);
    console.warn("FLIXORA SubDL search HTTP", response.status);
    return [];
  }
  const payload = await response.json() as JsonMap;
  if (payload.status !== true) return [];
  const titles = Array.isArray(payload.results) ? payload.results as JsonMap[] : [];
  if (!titleFallback && args.tmdbId > 0 &&
      !titles.some(x => Number(x.tmdb_id) === args.tmdbId)) return [];
  const rows = Array.isArray(payload.subtitles) ? payload.subtitles as JsonMap[] : [];
  const out: JsonMap[] = [];
  for (const row of rows) {
    const files = Array.isArray(row.unpack_files) ? row.unpack_files as JsonMap[] : [];
    for (const file of files) {
      const lang = languageCode(file.language);
      if (!args.languages.map(languageCode).includes(lang)) continue;
      if (args.mediaType === "tv" &&
          (Number(file.season) !== args.season || Number(file.episode) !== args.episode)) continue;
      const raw = new URL(String(file.url ?? ""), "https://dl.subdl.com").toString();
      const link = safeDownloadUrl(raw, "subdl.com");
      if (!link || !new URL(link).pathname.startsWith("/subtitle/")) continue;
      out.push({
        language: lang,
        format: String(file.format ?? "srt").toLowerCase(),
        fileName: String(file.name ?? "subtitle.srt").slice(0, 180),
        releaseName: String(file.release_name ?? row.release_name ?? row.name ?? "").slice(0, 180),
        downloadUrl: link,
        provider: "SubDL"
      });
    }
  }
  return out;
}
async function searchOpenSubtitles(args: SearchArgs, titleFallback = false, omitYear = false): Promise<JsonMap[]> {
  if (!args.apiKey.trim()) return [];
  const base = "https://api.opensubtitles.com/api/v1";
  const url = new URL(base + "/subtitles");
  if (!titleFallback && args.tmdbId > 0) {
    if (args.mediaType === "tv") {
      url.searchParams.set("parent_tmdb_id", String(args.tmdbId));
      url.searchParams.set("type", "episode");
      url.searchParams.set("season_number", String(args.season));
      url.searchParams.set("episode_number", String(args.episode));
    } else {
      url.searchParams.set("tmdb_id", String(args.tmdbId));
      url.searchParams.set("type", "movie");
    }
  } else {
    url.searchParams.set("query", args.title);
    url.searchParams.set("type", args.mediaType === "tv" ? "episode" : "movie");
    if (!omitYear && /^\d{4}$/.test(args.year)) url.searchParams.set("year", args.year);
    if (args.mediaType === "tv") {
      url.searchParams.set("season_number", String(args.season));
      url.searchParams.set("episode_number", String(args.episode));
    }
  }
  const requested = [...new Set(args.languages.map(languageCode))].sort();
  url.searchParams.set("languages", requested.join(","));
  const headers = {
    "Api-Key": args.apiKey,
    "User-Agent": "FLIXORA v1.0.12",
    "Accept": "application/json"
  };
  const response = await fetch(url, { headers, signal: AbortSignal.timeout(9000) });
  if (!response.ok) {
    args.providerErrors.push(`OpenSubtitles search HTTP ${response.status}`);
    console.warn("FLIXORA OpenSubtitles search HTTP", response.status);
    return [];
  }
  const payload = await response.json() as JsonMap;
  const rows = Array.isArray(payload.data) ? payload.data as JsonMap[] : [];
  const candidates: {row: JsonMap; attr: JsonMap; file: JsonMap; lang: string}[] = [];
  const seenLanguages = new Set<string>();
  for (const row of rows) {
    const attr = row.attributes && typeof row.attributes === "object" ? row.attributes as JsonMap : {};
    const lang = languageCode(attr.language);
    if (!requested.includes(lang) || seenLanguages.has(lang)) continue;
    const files = Array.isArray(attr.files) ? attr.files as JsonMap[] : [];
    const file = files.find(f => Number(f.file_id) > 0);
    if (!file) continue;
    // Only request one download link per language. The /download endpoint
    // consumes provider quota, so fetching every release for every language
    // at video startup needlessly exhausts the OpenSubtitles allowance.
    candidates.push({row, attr, file, lang});
    seenLanguages.add(lang);
  }
  const results: JsonMap[] = [];
  for (const candidate of candidates) {
    const id = Number(candidate.file.file_id);
    if (!Number.isInteger(id) || id <= 0) continue;
    try {
      const dl = await fetch(base + "/download", {
        method: "POST",
        headers: {...headers, "Content-Type": "application/json"},
        body: JSON.stringify({file_id: id}),
        signal: AbortSignal.timeout(9000)
      });
      if (!dl.ok) {
        const detail = (await dl.text()).slice(0, 180).replace(/[\\r\\n]+/g, " ").trim();
        const status = dl.status;
        // Provider quota/rate-limit blocks this provider only. Keep it as a
        // warning so another provider (for example SubDL) can still succeed.
        if (status !== 406 && status !== 429) {
          args.providerErrors.push(detail
            ? `OpenSubtitles download HTTP ${status}: ${detail}`
            : `OpenSubtitles download HTTP ${status}`);
        }
        console.warn("FLIXORA OpenSubtitles download stopped", status, detail);
        // 406 commonly means the provider's download allowance is exhausted;
        // 429 means the endpoint is rate-limiting. Further calls cannot help.
        if (status === 406 || status === 429) break;
        continue;
      }
      const result = await dl.json() as JsonMap;
      const link = safeDownloadUrl(result.link, "opensubtitles.com");
      if (!link) continue;
      const feature = candidate.attr.feature_details && typeof candidate.attr.feature_details === "object"
        ? candidate.attr.feature_details as JsonMap : {};
      const release = candidate.attr.release ?? feature.title ?? feature.movie_name ?? "";
      results.push({
        language: candidate.lang,
        format: String(candidate.file.file_name ?? "").split(".").pop()?.toLowerCase() || "srt",
        fileName: String(result.file_name ?? candidate.file.file_name ?? "subtitle.srt").slice(0, 180),
        releaseName: String(release).slice(0, 180),
        downloadUrl: link,
        provider: "OpenSubtitles"
      });
      // Keep requests comfortably below the provider's short-window limits.
      await new Promise(resolve => setTimeout(resolve, 300));
    } catch (error) {
      args.providerErrors.push("OpenSubtitles download request failed");
      console.warn("FLIXORA OpenSubtitles download request failed",
        error instanceof Error ? error.message : "unknown error");
    }
  }
  return results;
}
Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", {headers: corsHeaders});
  if (request.method !== "POST") return json({error: "Method not allowed"}, 405);
  try {
    const body = await request.json() as JsonMap;
    const tmdbId = Number(body.tmdbId ?? 0);
    const title = String(body.title ?? "").trim().slice(0, 180);
    const year = String(body.year ?? "").trim();
    const mediaType = body.mediaType === "tv" ? "tv" : "movie";
    const requested = String(body.languages ?? "EN").split(",")
      .map(x => x.trim().toUpperCase()).filter(x => supportedLanguages.has(x));
    const languages = [...new Set(requested)];
    if (!languages.length) languages.push("EN");
    const season = Math.max(0, Math.min(99, Number(body.season ?? 0) || 0));
    const episode = Math.max(0, Math.min(999, Number(body.episode ?? 0) || 0));
    if ((!Number.isInteger(tmdbId) || tmdbId <= 0) && !title)
      return json({error: "A valid TMDB ID or title is required."}, 400);
    if (mediaType === "tv" && (!season || !episode))
      return json({error: "Season and episode are required for TV subtitles."}, 400);
    const subdlKey = Deno.env.get("SUBDL_API_KEY")?.trim() ?? "";
    const openKey = Deno.env.get("OPENSUBTITLES_API_KEY")?.trim() ?? "";
    if (!subdlKey && !openKey) return json({error: "Subtitle service needs API setup."}, 503);
    const providerErrors: string[] = [];
    const baseArgs: SearchArgs = {apiKey:"", tmdbId, title, year, mediaType, languages, season, episode, providerErrors};
    const tasks: Promise<JsonMap[]>[] = [];
    if (subdlKey) tasks.push((async () => {
      try {
        let found = await searchSubDL({...baseArgs, apiKey: subdlKey});
        if (!found.length && tmdbId > 0 && title) found = await searchSubDL({...baseArgs, apiKey: subdlKey}, true);
        if (!found.length && title && year) found = await searchSubDL({...baseArgs, apiKey: subdlKey}, true, true);
        return found;
      } catch (error) {
        providerErrors.push("SubDL request failed");
        console.warn("FLIXORA SubDL request failed", error instanceof Error ? error.message : "unknown error");
        return [];
      }
    })());
    if (openKey) tasks.push((async () => {
      try {
        let found = await searchOpenSubtitles({...baseArgs, apiKey: openKey});
        // Do not repeat fallback searches when the provider has exhausted its
        // download quota or is rate-limiting this request.
        const downloadBlocked = () => providerErrors.some(error =>
          /OpenSubtitles download HTTP (?:406|429)/.test(error));
        if (!found.length && title && !downloadBlocked())
          found = await searchOpenSubtitles({...baseArgs, apiKey: openKey}, true);
        if (!found.length && title && year && !downloadBlocked())
          found = await searchOpenSubtitles({...baseArgs, apiKey: openKey}, true, true);
        return found;
      } catch (error) {
        providerErrors.push("OpenSubtitles request failed");
        console.warn("FLIXORA OpenSubtitles request failed", error instanceof Error ? error.message : "unknown error");
        return [];
      }
    })());
    const batches = await Promise.all(tasks);
    const subtitles = capAndDedupe(batches.flat());
    if (!subtitles.length) {
      const providerFailed = providerErrors.length > 0;
      return json({
        error: providerFailed
          ? "One or more subtitle providers could not complete the search. Please try again."
          : "No subtitles were found for the requested title, season, episode and languages.",
        searchedProviders: tasks.length,
        providerErrors,
      }, providerFailed ? 502 : 404);
    }
    const english = subtitles.find(x => x.language === "en");
    return json({
      subtitles,
      resultCount: subtitles.length,
      searchedProviders: tasks.length,
      ...(english ? {language:"English", format:english.format, fileName:english.fileName,
        releaseName:english.releaseName, downloadUrl:english.downloadUrl} : {})
    });
  } catch {
    return json({error: "Automatic subtitle lookup failed."}, 500);
  }
});