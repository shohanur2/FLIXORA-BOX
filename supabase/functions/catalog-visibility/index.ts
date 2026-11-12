import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Candidate = {
  key: string;
  tmdbId: number;
  mediaType: "movie" | "tv";
  title: string;
  year: string;
};

type AdminRow = {
  id: number;
  tmdb_id: number | null;
  title: string | null;
  release_date: string | null;
  media_type: string | null;
  is_published: boolean | null;
  created_at: string | null;
};

let cachedRows: AdminRow[] | null = null;
let cachedAt = 0;
let rowsInFlight: Promise<AdminRow[]> | null = null;

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return Response.json(body, {
    status,
    headers: {
      ...corsHeaders,
      "Cache-Control": "no-store",
    },
  });
}

function normalizeTitle(value: string): string {
  // Keep the same punctuation/whitespace normalization used by FLIXORA.
  return value
    .toLowerCase()
    .replace(/[\s\-_.:,;!?()\[\]{}]+/g, " ")
    .trim();
}

function yearOf(value: unknown): string {
  const date = String(value ?? "").trim();
  return /^\d{4}/.test(date) ? date.substring(0, 4) : "";
}

function serviceKey(): string {
  // The existing FLIXORA project uses legacy JWT-based keys. Prefer that key
  // while the project still provides it; the Supabase client can then use its
  // normal Authorization header without the new secret-key JWT limitation.
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (legacy) return legacy;

  const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS") ?? "";
  if (secretKeysRaw) {
    try {
      const secretKeys = JSON.parse(secretKeysRaw) as Record<string, string>;
      const preferred = secretKeys.default ??
        Object.values(secretKeys).find((value) => typeof value === "string");
      if (preferred) return preferred;
    } catch {
      // No usable server-side key was found.
    }
  }
  throw new Error("Supabase server key is not configured.");
}

async function loadAdminRows(): Promise<AdminRow[]> {
  if (cachedRows && Date.now() - cachedAt < 60_000) return cachedRows;
  if (rowsInFlight) return rowsInFlight;

  rowsInFlight = (async () => {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    if (!url) throw new Error("Supabase URL is not configured.");

    const admin = createClient(url, serviceKey(), {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    const rows: AdminRow[] = [];
    const pageSize = 500;
    const maximumRows = 10_000;

    for (let offset = 0; offset < maximumRows; offset += pageSize) {
      const { data, error } = await admin
        .from("movies")
        .select("id, tmdb_id, title, release_date, media_type, is_published, created_at")
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .range(offset, offset + pageSize - 1);

      if (error) throw error;
      const page = (data ?? []) as AdminRow[];
      rows.push(...page);
      if (page.length < pageSize) break;
    }

    cachedRows = rows;
    cachedAt = Date.now();
    return rows;
  })();

  try {
    return await rowsInFlight;
  } finally {
    rowsInFlight = null;
  }
}

function normalizeCandidates(value: unknown): Candidate[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 250).flatMap((raw): Candidate[] => {
    if (!raw || typeof raw !== "object") return [];
    const item = raw as Record<string, unknown>;
    const key = String(item.key ?? "").trim().slice(0, 256);
    const title = String(item.title ?? "").trim().slice(0, 180);
    const mediaType = item.mediaType === "tv" ? "tv" : "movie";
    const tmdbId = Number(item.tmdbId ?? 0);
    const rawYear = String(item.year ?? "").trim();
    const year = /^\d{4}$/.test(rawYear) ? rawYear : "";

    if (!key || !title || !Number.isSafeInteger(tmdbId) || tmdbId < 0) {
      return [];
    }
    return [{ key, title, mediaType, tmdbId, year }];
  });
}

function findBlockedKeys(rows: AdminRow[], candidates: Candidate[]): string[] {
  const latestByTmdb = new Map<string, AdminRow>();
  const latestByTitleYear = new Map<string, AdminRow>();
  const latestByTitleWithoutYear = new Map<string, AdminRow>();
  const latestByTitle = new Map<string, AdminRow>();

  // Rows arrive newest-first. The first matching Admin record is authoritative.
  for (const row of rows) {
    const mediaType = row.media_type === "tv" ? "tv" : "movie";
    const tmdbId = Number(row.tmdb_id ?? 0);
    const title = normalizeTitle(String(row.title ?? ""));
    const year = yearOf(row.release_date);

    if (tmdbId > 0) {
      const key = `${mediaType}:${tmdbId}`;
      if (!latestByTmdb.has(key)) latestByTmdb.set(key, row);
    }

    if (!title) continue;
    const base = `${mediaType}:${title}`;
    if (!latestByTitle.has(base)) latestByTitle.set(base, row);

    if (year) {
      const key = `${base}:${year}`;
      if (!latestByTitleYear.has(key)) latestByTitleYear.set(key, row);
    } else if (!latestByTitleWithoutYear.has(base)) {
      latestByTitleWithoutYear.set(base, row);
    }
  }

  const blocked: string[] = [];
  for (const candidate of candidates) {
    const title = normalizeTitle(candidate.title);
    const base = `${candidate.mediaType}:${title}`;
    const idMatch = candidate.tmdbId > 0
      ? latestByTmdb.get(`${candidate.mediaType}:${candidate.tmdbId}`)
      : undefined;
    const titleMatch = candidate.year
      ? latestByTitleYear.get(`${base}:${candidate.year}`) ??
        latestByTitleWithoutYear.get(base)
      : latestByTitle.get(base);
    const match = idMatch ?? titleMatch;

    if (match && match.is_published !== true) blocked.push(candidate.key);
  }

  return [...new Set(blocked)];
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await request.json() as Record<string, unknown>;
    const candidates = normalizeCandidates(body.candidates);
    if (Array.isArray(body.candidates) && body.candidates.length > 250) {
      return jsonResponse({ error: "Too many catalogue candidates" }, 413);
    }
    if (candidates.length === 0) {
      return jsonResponse({ blockedKeys: [], checked: 0 });
    }

    const rows = await loadAdminRows();
    return jsonResponse({
      blockedKeys: findBlockedKeys(rows, candidates),
      checked: candidates.length,
    });
  } catch {
    return jsonResponse({ error: "Could not check Admin publication status" }, 500);
  }
});
