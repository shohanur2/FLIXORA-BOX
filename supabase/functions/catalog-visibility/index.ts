import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Candidate = {
  key: string;
  sourceId: number;
};

type AdminRow = {
  id: number;
  is_published: boolean | null;
};

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

function normalizeCandidates(value: unknown): Candidate[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 250).flatMap((raw): Candidate[] => {
    if (!raw || typeof raw !== "object") return [];
    const item = raw as Record<string, unknown>;
    const key = String(item.key ?? "").trim().slice(0, 256);
    const source = String(item.source ?? "");
    const sourceId = Number(item.sourceId ?? 0);

    // Only exact Admin row identities are eligible for publication filtering.
    // MovieBox/TMDB candidates are deliberately ignored even if they share a
    // TMDB ID or title/year with an unpublished Admin row.
    if (
      source !== "admin" ||
      !key.startsWith("admin:id:") ||
      !Number.isSafeInteger(sourceId) ||
      sourceId <= 0 ||
      key !== `admin:id:${sourceId}`
    ) {
      return [];
    }

    return [{ key, sourceId }];
  });
}

function findBlockedKeys(
  rows: AdminRow[],
  candidates: Candidate[],
): string[] {
  const rowsById = new Map<number, AdminRow>(
    rows.map((row) => [Number(row.id), row]),
  );

  return candidates
    .filter((candidate) => {
      const row = rowsById.get(candidate.sourceId);
      // Missing/deleted Admin rows and unpublished rows are both hidden.
      return !row || row.is_published !== true;
    })
    .map((candidate) => candidate.key);
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

    const url = Deno.env.get("SUPABASE_URL") ?? "";
    if (!url) throw new Error("Supabase URL is not configured.");

    const admin = createClient(url, serviceKey(), {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });
    const sourceIds = [...new Set(candidates.map((item) => item.sourceId))];
    const { data, error } = await admin
      .from("movies")
      .select("id, is_published")
      .in("id", sourceIds);

    if (error) throw error;
    const rows = (data ?? []) as AdminRow[];
    return jsonResponse({
      blockedKeys: findBlockedKeys(rows, candidates),
      checked: candidates.length,
    });
  } catch {
    return jsonResponse({ error: "Could not check Admin publication status" }, 500);
  }
});
