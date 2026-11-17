import { unzipSync } from "npm:fflate@0.8.2";

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

const SUBSOURCE_BASE = "https://api.subsource.net/api/v1";
const subsourceLanguageAliases: Record<string, string> = {
  en:"en", english:"en", eng:"en", bn:"bn", bengali:"bn", bangla:"bn", ben:"bn",
  hi:"hi", hindi:"hi", hin:"hi", ur:"ur", urdu:"ur", urd:"ur", ar:"ar", arabic:"ar",
  es:"es", spanish:"es", spa:"es", fr:"fr", french:"fr", fra:"fr", fre:"fr",
  de:"de", german:"de", deu:"de", ger:"de", pt:"pt", portuguese:"pt", por:"pt",
  ru:"ru", russian:"ru", rus:"ru", ja:"ja", japanese:"ja", jpn:"ja",
  ko:"ko", korean:"ko", kor:"ko", zh:"zh", chinese:"zh", chi:"zh", zho:"zh",
  tr:"tr", turkish:"tr", tur:"tr", it:"it", italian:"it", ita:"it",
  nl:"nl", dutch:"nl", nld:"nl", pol:"pl", polish:"pl", pl:"pl",
  th:"th", thai:"th", tha:"th", id:"id", indonesian:"id", ind:"id",
  ms:"ms", malay:"ms", msa:"ms", fa:"fa", persian:"fa", farsi_persian:"fa",
};
function subsourceLanguageCode(value: unknown): string {
  const raw = String(value ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  return subsourceLanguageAliases[raw] ?? languageCode(raw);
}
function normalizeMatch(value: unknown): string {
  return String(value ?? "").toLowerCase().normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, " ").trim();
}
async function subsourceJson(url: URL, apiKey: string): Promise<JsonMap> {
  const response = await fetch(url, {
    headers: {"X-API-Key": apiKey, "Accept": "application/json"},
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error("SubSource HTTP " + response.status);
  const payload = await response.json() as JsonMap;
  return payload;
}
function subsourceReleaseInfo(value: unknown): string {
  return Array.isArray(value) ? value.map(x => String(x ?? "")).join(" ") : String(value ?? "");
}
function matchesSubSourceEpisode(release: string, season: number, episode: number): boolean {
  const compact = normalizeMatch(release).replace(/\s+/g, "");
  const s = String(season), ss = s.padStart(2,"0"), e = String(episode), ee = e.padStart(2,"0");
  const exact = ["s"+ss+"e"+ee,"s"+s+"e"+e,"s"+ss+"e"+e,"s"+s+"e"+ee,
    s+"x"+ee,s+"x"+e,ss+"x"+ee,ss+"x"+e];
  if (exact.some(x => compact.includes(x))) return true;
  const explicit = new RegExp("(?:^|[^a-z0-9])s0*"+season+"[-_. ]*e0*"+episode+"(?:[^0-9]|$)|(?:^|[^0-9])0*"+season+"x0*"+episode+"(?:[^0-9]|$)", "i");
  if (explicit.test(release)) return true;
  const otherEpisode = /\b(?:S\d{1,2}\s*E|E|EP(?:ISODE)?)\s*0*\d+\b/i;
  return !otherEpisode.test(release) && new RegExp("(?:^|[^0-9])0*"+episode+"(?:[^0-9]|$)").test(release);
}
async function searchSubSource(args: SearchArgs, apiKey: string): Promise<JsonMap[]> {
  const movieSearch = new URL(SUBSOURCE_BASE + "/movies/search");
  movieSearch.searchParams.set("searchType", "text");
  movieSearch.searchParams.set("q", args.title);
  movieSearch.searchParams.set("type", args.mediaType === "tv" ? "series" : "movie");
  if (/^\d{4}$/.test(args.year)) movieSearch.searchParams.set("year", args.year);
  if (args.mediaType === "tv") movieSearch.searchParams.set("season", String(args.season));
  const moviePayload = await subsourceJson(movieSearch, apiKey);
  const movieRows = Array.isArray(moviePayload.data) ? moviePayload.data as JsonMap[] : [];
  const wantedTitle = normalizeMatch(args.title);
  const scored = movieRows.map(row => {
    const id = Number(row.movieId ?? row.id ?? 0);
    const type = String(row.type ?? "").toLowerCase();
    if (args.mediaType === "tv" && type && type !== "series" && type !== "tv") return {id, score:0};
    if (args.mediaType !== "tv" && type && type !== "movie") return {id, score:0};
    const rowTmdbId = Number(row.tmdbId ?? 0);
    if (args.tmdbId > 0 && rowTmdbId > 0 && rowTmdbId !== args.tmdbId) return {id, score:0};
    const titleMatches = normalizeMatch(row.title) === wantedTitle ||
      normalizeMatch(row.alternateTitle) === wantedTitle;
    if (!titleMatches) return {id, score:0};
    const releaseYear = Number(row.releaseYear ?? 0);
    if (args.year && releaseYear > 0 && releaseYear !== Number(args.year)) return {id, score:0};
    let score = 10;
    if (args.tmdbId > 0 && rowTmdbId === args.tmdbId) score += 20;
    if (args.year && releaseYear === Number(args.year)) score += 2;
    return {id, score};
  }).filter(x => Number.isSafeInteger(x.id) && x.id > 0 && x.score >= 10)
    .sort((a,b) => b.score-a.score);
  const movieId = scored[0]?.id;
  if (!movieId) return [];
  const subtitleUrl = new URL(SUBSOURCE_BASE + "/subtitles");
  subtitleUrl.searchParams.set("movieId", String(movieId));
  subtitleUrl.searchParams.set("sort", "rating");
  subtitleUrl.searchParams.set("limit", "100");
  const subtitlePayload = await subsourceJson(subtitleUrl, apiKey);
  const rows = Array.isArray(subtitlePayload.data) ? subtitlePayload.data as JsonMap[] : [];
  const requested = new Set(args.languages.map(languageCode));
  const output: JsonMap[] = [];
  const seen = new Set<string>();
  for (const row of rows) {
    const id = Number(row.subtitleId ?? row.id ?? 0);
    if (!Number.isInteger(id) || id <= 0) continue;
    const lang = subsourceLanguageCode(row.language ?? row.languageName ?? row.languageCode);
    if (!requested.has(lang)) continue;
    const release = subsourceReleaseInfo(row.releaseInfo ?? row.release_info);
    if (seen.has(lang + ":" + id)) continue;
    seen.add(lang + ":" + id);
    output.push({
      language: lang, format: "srt", fileName: "subtitle.srt",
      releaseName: release.slice(0,180), downloadUrl: "subsource://" + id,
      subsourceId: id, provider: "SubSource",
    });
    if (output.length >= 40) break;
  }
  return output;
}
function validateSubSourceZipLimits(archive: Uint8Array): void {
  const view = new DataView(archive.buffer, archive.byteOffset, archive.byteLength);
  const minimum = Math.max(0, archive.length - 65557);
  let endRecord = -1;
  for (let offset = archive.length - 22; offset >= minimum; offset--) {
    if (view.getUint32(offset, true) === 0x06054b50) {
      endRecord = offset;
      break;
    }
  }
  if (endRecord < 0) throw new Error("ZIP end record is missing.");
  const entryCount = view.getUint16(endRecord + 10, true);
  const centralSize = view.getUint32(endRecord + 12, true);
  const centralOffset = view.getUint32(endRecord + 16, true);
  if (entryCount < 1 || entryCount > 100 ||
      centralOffset + centralSize > endRecord || centralOffset >= archive.length) {
    throw new Error("ZIP archive structure or file count is invalid.");
  }
  let offset = centralOffset;
  let totalUncompressed = 0;
  for (let index = 0; index < entryCount; index++) {
    if (offset + 46 > archive.length || view.getUint32(offset, true) !== 0x02014b50) {
      throw new Error("ZIP central directory is invalid.");
    }
    const compressed = view.getUint32(offset + 20, true);
    const uncompressed = view.getUint32(offset + 24, true);
    const nameLength = view.getUint16(offset + 28, true);
    const extraLength = view.getUint16(offset + 30, true);
    const commentLength = view.getUint16(offset + 32, true);
    if (compressed === 0xffffffff || uncompressed === 0xffffffff ||
        uncompressed > 5 * 1024 * 1024) {
      throw new Error("ZIP entry exceeds the subtitle extraction size limit.");
    }
    totalUncompressed += uncompressed;
    if (totalUncompressed > 20 * 1024 * 1024) {
      throw new Error("ZIP archive exceeds the total extraction size limit.");
    }
    offset += 46 + nameLength + extraLength + commentLength;
    if (offset > centralOffset + centralSize) {
      throw new Error("ZIP central directory bounds are invalid.");
    }
  }
}
function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  }
  return btoa(binary);
}
function chooseSubSourceArchiveFile(files: Record<string, Uint8Array>, releaseName: string,
  season: number, episode: number, mediaType: string): {name:string; bytes:Uint8Array} {
  const candidates = Object.entries(files).filter(([name, bytes]) =>
    /\.(srt|ass|ssa|vtt)$/i.test(name) && bytes.length >= 8 && bytes.length <= 5 * 1024 * 1024 &&
    !name.split(/[\\/]/).some(part => part === ".."));
  if (!candidates.length) throw new Error("SubSource ZIP contains no supported subtitle file");
  if (candidates.length === 1) {
    const only = candidates[0];
    const episodeMarker = /(?:S\d{1,2}\s*E\d{1,3}|\b\d{1,2}x\d{1,3}\b)/i;
    const fileHasEpisode = episodeMarker.test(only[0]);
    const releaseHasEpisode = episodeMarker.test(releaseName);
    if (mediaType === "tv" &&
        ((fileHasEpisode && !matchesSubSourceEpisode(only[0], season, episode)) ||
         (!fileHasEpisode && releaseHasEpisode && !matchesSubSourceEpisode(releaseName, season, episode)))) {
      throw new Error("SubSource archive contains a different TV episode.");
    }
    return {name:only[0], bytes:only[1]};
  }
  const episodeMatches = mediaType === "tv"
    ? candidates.filter(([name]) => matchesSubSourceEpisode(name, season, episode))
    : candidates;
  const release = normalizeMatch(releaseName);
  const releaseMatches = episodeMatches.filter(([name]) => {
    const normalized = normalizeMatch(name).replace(/\.(srt|ass|ssa|vtt)$/i,"");
    return release.length > 5 && (normalized.includes(release) || release.includes(normalized));
  });
  const pool = releaseMatches.length ? releaseMatches : episodeMatches;
  if (pool.length !== 1) throw new Error("SubSource archive has multiple subtitle files and no unambiguous episode/release match");
  return {name:pool[0][0], bytes:pool[0][1]};
}
async function downloadSubSource(body: JsonMap): Promise<Response> {
  const apiKey = Deno.env.get("SUBSOURCE_API_KEY")?.trim() ?? "";
  if (!apiKey) return json({error:"SubSource API key is not configured."},503);
  const id = Number(body.subtitleId ?? 0);
  if (!Number.isSafeInteger(id) || id <= 0) return json({error:"Invalid SubSource subtitle ID."},400);
  const response = await fetch(SUBSOURCE_BASE + "/subtitles/" + id + "/download", {
    headers: {"X-API-Key":apiKey,"Accept":"application/zip, application/octet-stream, */*"},
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) return json({error:"SubSource download HTTP " + response.status + "."},502);
  const archive = new Uint8Array(await response.arrayBuffer());
  if (archive.length < 22 || archive.length > 10 * 1024 * 1024 ||
      archive[0] !== 0x50 || archive[1] !== 0x4b) {
    return json({error:"SubSource returned an invalid or oversized subtitle archive."},502);
  }
  let extracted: Record<string, Uint8Array>;
  try {
    validateSubSourceZipLimits(archive);
    extracted = unzipSync(archive);
  }
  catch { return json({error:"Could not extract the SubSource subtitle archive."},502); }
  try {
    const selected = chooseSubSourceArchiveFile(extracted,String(body.releaseName ?? ""),
      Number(body.season ?? 0),Number(body.episode ?? 0),body.mediaType === "tv" ? "tv" : "movie");
    return json({contentBase64:base64Encode(selected.bytes),
      fileName:selected.name.split(/[\\/]/).pop() ?? "subtitle.srt",
      extension:selected.name.split(".").pop()?.toLowerCase() ?? "srt"});
  } catch (error) {
    return json({error:error instanceof Error ? error.message : "Could not select a matching subtitle file."},422);
  }
}


const iSubLang: Record<string,string> = {en:"english",bn:"bengali",hi:"hindi",ur:"urdu",ar:"arabic",es:"spanish",fr:"french",de:"german",pt:"portuguese",ru:"russian",ja:"japanese",ko:"korean",it:"italian",nl:"dutch",pl:"polish",th:"thai",id:"indonesian",ms:"malay",fa:"farsi-persian",zh:"chinese-bg-code"};
const bollyLang: Record<string,string> = {en:"eng",hi:"hin",ar:"ara",es:"spn",fr:"fra",de:"ger",pt:"por",ru:"rus",ja:"jpn",ko:"kor",it:"ita",nl:"dut",pl:"pol",th:"tha",ms:"may",fa:"per",zh:"chi"};
function stripHtml(s:string):string{return s.replace(/<[^>]*>/g," ").replace(/&nbsp;/gi," ").replace(/&amp;/gi,"&").replace(/&#39;|&apos;/gi,"'").replace(/&quot;/gi,'"').replace(/\s+/g," ").trim();}
async function getProviderPage(raw:string,host:string,referer?:string,method="GET",body?:string):Promise<string>{
 const url=safeDownloadUrl(raw,host); if(!url) throw new Error("Unsafe provider URL");
 const headers:Record<string,string>={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125 Safari/537.36","Accept":"text/html,application/xhtml+xml,*/*","Accept-Language":"en-US,en;q=0.9"};
 if(referer) headers.Referer=referer;
 if(body!==undefined) headers["Content-Type"]="application/x-www-form-urlencoded";
 const response=await fetch(url,{method,headers,body,signal:AbortSignal.timeout(12000)});
 if(!response.ok) throw new Error("Provider HTTP "+response.status);
 return await response.text();
}
function providerAbsolute(path:string,base:string):string{return new URL(path,base).toString();}
function titleMatch(a:string,b:string):boolean{
 const x=normalizeMatch(a).replace(/\b(19|20)\d{2}\b/g,"").trim();
 const y=normalizeMatch(b).replace(/\b(19|20)\d{2}\b/g,"").trim();
 return !!x&&(x===y||x.startsWith(y+" ")||y.startsWith(x+" "));
}
async function searchISubtitles(args:SearchArgs):Promise<JsonMap[]>{
 const base="https://isubtitles.org",host="isubtitles.org";
 const searchUrl=base+"/search?kwd="+encodeURIComponent(args.title);
 const html=await getProviderPage(searchUrl,host);
 const pages=[...html.matchAll(/<h3>\s*<a\b[^>]*href=["']([^"']+-subtitles)["'][^>]*>([\s\S]*?)<\/a>\s*<\/h3>/gi)]
  .map(m=>({url:providerAbsolute(m[1],base),slug:m[1].split("/").filter(Boolean).pop()?.replace(/-subtitles$/,"")||"",title:stripHtml(m[2])}))
  .filter(p=>p.slug&&titleMatch(p.title,args.title)).slice(0,3);
 const out:JsonMap[]=[];
 for(const page of pages){
  for(const lang of args.languages.map(languageCode)){
   const slug=iSubLang[lang]; if(!slug) continue;
   let listing=""; const listUrl=base+"/"+page.slug+"/"+slug;
   try{listing=await getProviderPage(listUrl,host,searchUrl);}catch{continue;}
   for(const row of listing.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)){
    const link=row[1].match(/href=["'](\/download\/[^"'<>]+)["']/i); if(!link) continue;
    const url=providerAbsolute(link[1],base); if(!safeDownloadUrl(url,host)) continue;
    const releaseCell=row[1].match(/data-title=["']Release\s*\/\s*Movie["'][^>]*>([\s\S]*?)<\/td>/i);
    const release=releaseCell?stripHtml(releaseCell[1]):page.title;
    if(args.mediaType==="tv"){
     const exact=new RegExp("(?:s0*"+args.season+"\\s*e0*"+args.episode+"|"+args.season+"x0*"+args.episode+")","i");
     if(/(?:s\d{1,2}\s*e\d{1,3}|\b\d{1,2}x\d{1,3}\b)/i.test(release)&&!exact.test(release)) continue;
    }
    const id=link[1].split("/").filter(Boolean).pop()||"";
    out.push({language:lang,format:"zip",fileName:"isubtitles_"+id+".zip",releaseName:release.slice(0,180),downloadUrl:url,pageUrl:listUrl,provider:"iSubtitles",providerSource:"isubtitles"});
    if(out.length>=20)return out;
   }
  }
  if(out.length)break;
 }
 return out;
}
async function searchBollyNook(args:SearchArgs):Promise<JsonMap[]>{
 if(args.mediaType!=="movie")return [];
 const base="https://www.bollynook.com",host="bollynook.com",out:JsonMap[]=[];
 for(const lang of args.languages.map(languageCode)){
  const code=bollyLang[lang];if(!code)continue;
  const searchUrl=base+"/en/search/";
  const form=new URLSearchParams({type:"2",title:args.title+(args.year?" "+args.year:""),language:code,submit:"Search"}).toString();
  let html="";try{html=await getProviderPage(searchUrl,host,base+"/en/","POST",form);}catch{continue;}
  const links=[...html.matchAll(/href=["'](\/en\/bollywood-movie-subtitles\/\d+\/[^"']+\/)["'][^>]*>([\s\S]*?)<\/a>/gi)];
  for(const match of links.slice(0,5)){
   const title=stripHtml(match[2]);if(!titleMatch(title,args.title))continue;
   const detailUrl=providerAbsolute(match[1],base);
   let detail="";try{detail=await getProviderPage(detailUrl,host,searchUrl);}catch{continue;}
   const year=detail.match(/Year:\s*<strong>(\d{4})<\/strong>/i);
   if(args.year&&year&&Number(year[1])!==Number(args.year))continue;
   const dl=detail.match(/<a\b[^>]*class=["'][^"']*\bdownloads\b[^"']*["'][^>]*href=["']([^"']+)["']/i);
   if(!dl)continue;
   const url=providerAbsolute(dl[1],base);if(!safeDownloadUrl(url,host))continue;
   out.push({language:lang,format:"zip",fileName:"bollynook_subtitle.zip",releaseName:(title+(year?" "+year[1]:"")).slice(0,180),downloadUrl:url,pageUrl:detailUrl,provider:"BollyNook",providerSource:"bollynook"});
   break;
  }
 }
 return out;
}
function selectExternalArchive(files:Record<string,Uint8Array>,season:number,episode:number,mediaType:string):{name:string;bytes:Uint8Array}{
 const candidates=Object.entries(files).filter(([n,b])=>/\.(srt|ass|ssa|vtt)$/i.test(n)&&b.length>=16&&b.length<=5*1024*1024&&!n.split(/[\\/]/).includes(".."));
 if(!candidates.length)throw new Error("Provider archive has no valid subtitle");
 if(mediaType==="tv"){
  const exact=candidates.filter(([n])=>matchesSubSourceEpisode(n,season,episode));
  if(exact.length===1)return{name:exact[0][0],bytes:exact[0][1]};
  if(exact.length>1||candidates.length>1)throw new Error("Provider archive has no unambiguous exact episode subtitle");
  if(/(?:s\d{1,2}\s*e\d{1,3}|\b\d{1,2}x\d{1,3}\b)/i.test(candidates[0][0]))throw new Error("Provider archive is for a different episode");
 }
 if(candidates.length!==1)throw new Error("Provider archive contains multiple subtitle files");
 return{name:candidates[0][0],bytes:candidates[0][1]};
}
async function downloadProviderSubtitle(body:JsonMap):Promise<Response>{
 const provider=String(body.provider??"").toLowerCase();
 const host=provider==="isubtitles"?"isubtitles.org":provider==="bollynook"?"bollynook.com":"";
 if(!host)return json({error:"Unsupported subtitle provider."},400);
 const url=safeDownloadUrl(body.downloadUrl,host);if(!url)return json({error:"Invalid provider download URL."},400);
 const referer=safeDownloadUrl(body.pageUrl,host);
 const response=await fetch(url,{headers:{"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125 Safari/537.36","Accept":"application/zip,application/octet-stream,text/plain,*/*",...(referer?{"Referer":referer}:{})},signal:AbortSignal.timeout(20000)});
 if(!response.ok)return json({error:provider+" download HTTP "+response.status},502);
 const bytes=new Uint8Array(await response.arrayBuffer());
 if(bytes.length<16||bytes.length>10*1024*1024)return json({error:"Provider returned an empty or oversized subtitle."},502);
 let selected:Uint8Array,name="subtitle.srt";
 if(bytes[0]===0x50&&bytes[1]===0x4b){
  try{const files=unzipSync(bytes);const file=selectExternalArchive(files,Number(body.season??0),Number(body.episode??0),body.mediaType==="tv"?"tv":"movie");selected=file.bytes;name=file.name.split(/[\\/]/).pop()||name;}
  catch(error){return json({error:error instanceof Error?error.message:"Could not extract subtitle archive."},422);}
 }else{
  const type=(response.headers.get("content-type")??"").toLowerCase();
  if(type.includes("text/html")||bytes[0]===0x3c)return json({error:"Provider returned an HTML page, not a subtitle."},502);
  selected=bytes;
 }
 if(selected.length<16||selected.length>5*1024*1024)return json({error:"Extracted subtitle is invalid or too large."},422);
 return json({contentBase64:base64Encode(selected),fileName:name,extension:name.split(".").pop()||"srt"});
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", {headers: corsHeaders});
  if (request.method !== "POST") return json({error: "Method not allowed"}, 405);
  try {
    const body = await request.json() as JsonMap;
    if (body.action === "download_subsource") return await downloadSubSource(body);
    if (body.action === "download_provider_subtitle") return await downloadProviderSubtitle(body);
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
    const subsourceKey = Deno.env.get("SUBSOURCE_API_KEY")?.trim() ?? "";

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
    // All provider searches run independently; one failed website cannot
    // prevent results from the other sources.
    if (subsourceKey) tasks.push((async () => {
      try { return await searchSubSource(baseArgs, subsourceKey); }
      catch (error) { providerErrors.push("SubSource request failed"); console.warn("FLIXORA SubSource failed",error); return []; }
    })());
    tasks.push((async () => {
      try { return await searchISubtitles(baseArgs); }
      catch (error) { providerErrors.push("iSubtitles request failed"); console.warn("FLIXORA iSubtitles failed",error); return []; }
    })());
    if(mediaType==="movie") tasks.push((async () => {
      try { return await searchBollyNook(baseArgs); }
      catch (error) { providerErrors.push("BollyNook request failed"); console.warn("FLIXORA BollyNook failed",error); return []; }
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