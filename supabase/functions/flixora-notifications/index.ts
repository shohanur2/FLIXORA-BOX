import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type MovieRecord = {
  id?: number | string;
  title?: string;
  media_type?: string;
  is_published?: boolean;
};

type WebhookPayload = {
  type?: string;
  table?: string;
  record?: MovieRecord | null;
  old_record?: MovieRecord | null;
  event_type?: string;
  release_tag?: string;
  release_name?: string;
};

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function equalSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

async function getGoogleAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
  token_uri?: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = encodeJson({ alg: "RS256", typ: "JWT" });
  const claim = encodeJson({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  });
  const unsigned = header + "." + claim;
  const pem = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const assertion = unsigned + "." + base64Url(signature);
  const tokenResponse = await fetch(
    serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    },
  );
  if (!tokenResponse.ok) {
    throw new Error("Google OAuth token exchange failed");
  }
  const tokenData = await tokenResponse.json();
  return tokenData.access_token as string;
}

async function sendTopicNotification(
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<void> {
  const rawServiceAccount = Deno.env.get("FLIXORA_FIREBASE_SERVICE_ACCOUNT");
  if (!rawServiceAccount) {
    throw new Error("Missing FLIXORA_FIREBASE_SERVICE_ACCOUNT secret");
  }
  const serviceAccount = JSON.parse(rawServiceAccount);
  const projectId = serviceAccount.project_id;
  if (!projectId || !serviceAccount.client_email || !serviceAccount.private_key) {
    throw new Error("Firebase service account JSON is incomplete");
  }

  const accessToken = await getGoogleAccessToken(serviceAccount);
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          topic: "flixora_all_updates",
          notification: { title, body },
          data,
          android: {
            priority: "HIGH",
            notification: { channel_id: "flixora_updates" },
          },
        },
      }),
    },
  );
  if (!response.ok) {
    const detail = await response.text();
    console.error("FCM send failed:", response.status, detail);
    throw new Error("Firebase Cloud Messaging rejected the notification");
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const expectedSecret = Deno.env.get("FLIXORA_NOTIFICATION_WEBHOOK_SECRET");
  const suppliedSecret = req.headers.get("x-flixora-webhook-secret") ?? "";
  if (!expectedSecret || !equalSecret(suppliedSecret, expectedSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const payload = await req.json() as WebhookPayload;

    if (payload.event_type === "app_release") {
      const version = payload.release_tag ?? payload.release_name ?? "New version";
      await sendTopicNotification(
        "FLIXORA update available",
        `Version ${version} is now available. Update FLIXORA to enjoy the latest improvements.`,
        { type: "app_update", version },
      );
      return Response.json({ sent: true, type: "app_update" });
    }

    if (payload.table !== "movies") {
      return Response.json({ sent: false, reason: "ignored_table" });
    }

    const record = payload.record;
    if (!record || record.is_published !== true) {
      return Response.json({ sent: false, reason: "not_published" });
    }

    const wasPublished = payload.old_record?.is_published === true;
    if (payload.type === "UPDATE" && wasPublished) {
      return Response.json({ sent: false, reason: "already_published" });
    }
    if (payload.type !== "INSERT" && payload.type !== "UPDATE") {
      return Response.json({ sent: false, reason: "ignored_event" });
    }

    const name = (record.title ?? "A new title").trim() || "A new title";
    const mediaType = record.media_type === "tv" ? "series" : "movie";
    await sendTopicNotification(
      "New on FLIXORA",
      `${name} is now available to watch.`,
      {
        type: "new_content",
        media_type: mediaType,
        content_id: String(record.id ?? ""),
      },
    );
    return Response.json({ sent: true, type: "new_content" });
  } catch (error) {
    console.error("FLIXORA notification webhook failed:", error);
    return Response.json({ error: "Notification delivery failed" }, { status: 500 });
  }
});
