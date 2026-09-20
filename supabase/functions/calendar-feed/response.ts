import { calendar, type DisconnectedFeed, type FeedEvent } from "./calendar.ts";

const headers = {
  "Content-Type": "text/calendar; charset=utf-8",
  "Cache-Control": "private, no-cache",
  "Content-Disposition": 'inline; filename="schedule.ics"',
};

export async function feedResponse(
  request: Request,
  events: FeedEvent[],
  feedUpdatedAt: string | null,
  disconnected?: DisconnectedFeed,
): Promise<Response> {
  const body = calendar(events, feedUpdatedAt, disconnected);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  const etag = `"${Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("")}"`;
  const responseHeaders = new Headers(headers);
  responseHeaders.set("ETag", etag);
  if (feedUpdatedAt) {
    responseHeaders.set("Last-Modified", new Date(feedUpdatedAt).toUTCString());
  }
  const ifNoneMatch = request.headers.get("If-None-Match");
  const matchesEtag = ifNoneMatch?.split(",").some((tag) => {
    const value = tag.trim();
    return value === "*" || value.replace(/^W\//, "") === etag;
  });
  const ifModifiedSince = request.headers.get("If-Modified-Since");
  const since = ifModifiedSince ? Date.parse(ifModifiedSince) : NaN;
  const matchesDate = !ifNoneMatch && feedUpdatedAt && !Number.isNaN(since) &&
    new Date(feedUpdatedAt).getTime() <= since;
  return matchesEtag || matchesDate
    ? new Response(null, { status: 304, headers: responseHeaders })
    : new Response(body, { status: 200, headers: responseHeaders });
}
