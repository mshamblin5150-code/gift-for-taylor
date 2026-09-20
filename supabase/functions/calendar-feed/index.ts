import type { FeedEvent } from "./calendar.ts";
import { feedResponse } from "./response.ts";

async function rpc<T>(name: string, params: Record<string, string | null>): Promise<T> {
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
    body: JSON.stringify(params),
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
    const owner = await rpc<string | null>("record_calendar_feed_fetch", {
      p_token: token,
      p_user_agent: request.headers.get("user-agent"),
      p_if_none_match: request.headers.get("if-none-match"),
      p_if_modified_since: request.headers.get("if-modified-since"),
      p_forwarded_for: request.headers.get("x-forwarded-for"),
    });
    if (!owner) return new Response(null, { status: 404 });
    const [events, feedUpdatedAt] = await Promise.all([
      rpc<FeedEvent[]>("calendar_feed_events", { p_token: token }),
      rpc<string | null>("calendar_feed_last_modified", { p_token: token }),
    ]);
    return await feedResponse(request, events, feedUpdatedAt);
  } catch (error) {
    console.error(error);
    return new Response(null, { status: 503 });
  }
});
