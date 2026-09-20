import type { FeedEvent } from "./calendar.ts";
import { feedResponse } from "./response.ts";

async function rpc<T>(name: string, token: string): Promise<T> {
  const base = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !key) throw new Error("Calendar feed is not configured");
  const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_token: token }),
  });
  if (!response.ok) {
    throw new Error(`Calendar feed query failed: ${response.status}`);
  }
  return await response.json() as T;
}

Deno.serve(async (request) => {
  if (request.method !== "GET") return new Response(null, { status: 405 });
  const token = new URL(request.url).pathname.split("/").at(-1) ?? "";
  if (!/^[0-9a-f]{64}$/.test(token)) return new Response(null, { status: 404 });
  try {
    const owner = await rpc<string | null>("calendar_feed_owner", token);
    if (!owner) return new Response(null, { status: 404 });
    const [events, feedUpdatedAt] = await Promise.all([
      rpc<FeedEvent[]>("calendar_feed_events", token),
      rpc<string | null>("calendar_feed_last_modified", token),
    ]);
    return await feedResponse(request, events, feedUpdatedAt);
  } catch (error) {
    console.error(error);
    return new Response(null, { status: 503 });
  }
});
