import { calendar, type FeedEvent } from "./calendar.ts";

const headers = {
  "Content-Type": "text/calendar; charset=utf-8",
  "Cache-Control": "no-store, private",
  "Content-Disposition": 'inline; filename="schedule.ics"',
};

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
    });
    if (!owner) return new Response(null, { status: 404 });
    const events = await rpc<FeedEvent[]>("calendar_feed_events", { p_token: token });
    return new Response(calendar(events), { status: 200, headers });
  } catch (error) {
    console.error(error);
    return new Response(null, { status: 503 });
  }
});
