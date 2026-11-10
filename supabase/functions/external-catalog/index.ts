const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type JsonMap = Record<string, unknown>;

async function getJson(url: URL, headers: Record<string, string> = {}) {
  try {
    const response = await fetch(url, {
      headers,
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: corsHeaders },
    );
  }

  try {
    const body = await request.json() as JsonMap;
    const title = String(body.title ?? "").trim().slice(0, 180);
    const year = String(body.year ?? "").trim();
    const mediaType = body.mediaType === "tv" ? "tv" : "movie";
    const tmdbId = Number(body.tmdbId ?? 0);
    const rawRegion = String(body.region ?? "BD").trim().toUpperCase();
    const region = /^[A-Z]{2}$/.test(rawRegion) ? rawRegion : "BD";

    if (!title) {
      return Response.json(
        { error: "A title is required" },
        { status: 400, headers: corsHeaders },
      );
    }

    const omdbKey = Deno.env.get("OMDB_API_KEY") ?? "";
    const watchmodeKey = Deno.env.get("WATCHMODE_API_KEY") ?? "";
    const tasteDiveKey = Deno.env.get("TASTEDIVE_API_KEY") ?? "";
    const traktClientId = Deno.env.get("TRAKT_CLIENT_ID") ?? "";

    const omdbPromise = (async () => {
      if (!omdbKey) return null;
      const url = new URL("https://www.omdbapi.com/");
      url.searchParams.set("apikey", omdbKey);
      url.searchParams.set("t", title);
      url.searchParams.set("type", mediaType === "tv" ? "series" : "movie");
      url.searchParams.set("plot", "short");
      if (/^\d{4}$/.test(year)) url.searchParams.set("y", year);
      const result = await getJson(url);
      if (!result || result.Response !== "True") return null;
      const fields = [
        "imdbRating", "Metascore", "Rated", "Runtime", "Awards",
        "imdbVotes", "BoxOffice", "Country", "Language",
      ];
      const clean: JsonMap = {};
      for (const field of fields) clean[field] = result[field] ?? "";
      return clean;
    })();

    const watchmodePromise = (async () => {
      if (!watchmodeKey || !Number.isInteger(tmdbId) || tmdbId <= 0) return [];
      const kind = mediaType === "tv" ? "tv" : "movie";
      const url = new URL(
        `https://api.watchmode.com/v1/title/${kind}-${tmdbId}/sources/`,
      );
      url.searchParams.set("apiKey", watchmodeKey);
      url.searchParams.set("regions", region);
      const result = await getJson(url);
      if (!Array.isArray(result)) return [];
      return result.slice(0, 12).map((item: JsonMap) => ({
        name: item.name ?? "",
        type: item.type ?? "",
        region: item.region ?? region,
        format: item.format ?? "",
        price: item.price ?? "",
        web_url: item.web_url ?? "",
      }));
    })();

    const tasteDivePromise = (async () => {
      if (!tasteDiveKey) return [];
      const kind = mediaType === "tv" ? "show" : "movie";
      const url = new URL("https://tastedive.com/api/similar");
      url.searchParams.set("k", tasteDiveKey);
      url.searchParams.set("q", `${kind}:${title}`);
      url.searchParams.set("type", kind);
      url.searchParams.set("info", "1");
      url.searchParams.set("limit", "8");
      const result = await getJson(url);
      const similar = result && typeof result === "object"
        ? (result as JsonMap).Similar
        : null;
      const rows = similar && typeof similar === "object"
        ? (similar as JsonMap).Results
        : null;
      if (!Array.isArray(rows)) return [];
      return rows.slice(0, 8).map((item: JsonMap) => ({
        Name: item.Name ?? "",
        Type: item.Type ?? "",
        wTeaser: item.wTeaser ?? "",
      }));
    })();

    const traktPromise = (async () => {
      if (!traktClientId || !Number.isInteger(tmdbId) || tmdbId <= 0) {
        return null;
      }
      const kind = mediaType === "tv" ? "show" : "movie";
      const url = new URL(`https://api.trakt.tv/search/tmdb/${tmdbId}`);
      url.searchParams.set("type", kind);
      url.searchParams.set("extended", "full");
      const result = await getJson(url, {
        "Content-Type": "application/json",
        "trakt-api-version": "2",
        "trakt-api-key": traktClientId,
        "User-Agent": "FLIXORA/1.0.9",
      });
      if (!Array.isArray(result) || result.length === 0) return null;
      const item = result[0]?.[kind];
      if (!item || typeof item !== "object") return null;
      const ids = (item as JsonMap).ids;
      const traktId = ids && typeof ids === "object"
        ? (ids as JsonMap).trakt
        : null;
      return {
        rating: (item as JsonMap).rating ?? null,
        votes: (item as JsonMap).votes ?? null,
        rank: (item as JsonMap).rank ?? null,
        traktUrl: typeof traktId === "number"
          ? `https://trakt.tv/${kind}/${traktId}`
          : "",
      };
    })();

    const [omdb, watchmode, similar, trakt] = await Promise.all([
      omdbPromise,
      watchmodePromise,
      tasteDivePromise,
      traktPromise,
    ]);

    return Response.json(
      { omdb, watchmode, similar, trakt },
      { headers: { ...corsHeaders, "Cache-Control": "public, max-age=900" } },
    );
  } catch {
    return Response.json(
      { error: "External catalogue lookup failed" },
      { status: 500, headers: corsHeaders },
    );
  }
});
