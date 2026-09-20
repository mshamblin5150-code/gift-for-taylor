import type { FeedEvent } from "./calendar.ts";
import { feedResponse } from "./response.ts";

async function rpc<T>(
  name: string,
  params: Record<string, string | null>,
): Promise<T> {
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

type FeedState = {
  state: "live" | "ended" | "feed" | "invitations";
  subscription_id: string;
  staff_member_id: string;
  revoked_at: string | null;
  last_modified: string | null;
  events: FeedEvent[];
};

type QueryState = (
  params: Record<string, string | null>,
) => Promise<FeedState | null>;

const queryState: QueryState = (params) => rpc("calendar_feed_state", params);

export async function handleRequest(
  request: Request,
  query: QueryState = queryState,
): Promise<Response> {
  if (request.method !== "GET") return new Response(null, { status: 405 });
  const token = new URL(request.url).pathname.split("/").at(-1) ?? "";
  if (!/^[0-9a-f]{64}$/.test(token)) return new Response(null, { status: 404 });
  try {
    const state = await query({
      p_token: token,
      p_user_agent: request.headers.get("user-agent"),
      p_if_none_match: request.headers.get("if-none-match"),
      p_if_modified_since: request.headers.get("if-modified-since"),
      p_forwarded_for: request.headers.get("x-forwarded-for"),
    });
    if (!state) return new Response(null, { status: 404 });
    const disconnected = state.state === "live" ? undefined : {
      state: state.state,
      subscriptionId: state.subscription_id,
      revokedAt: state.revoked_at!,
    };
    return await feedResponse(
      request,
      state.events,
      state.last_modified,
      disconnected,
    );
  } catch (error) {
    console.error(error);
    return new Response(null, { status: 503 });
  }
}
