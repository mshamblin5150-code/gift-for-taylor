import { calendar } from "./calendar.ts";
import { feedResponse } from "./response.ts";
import { handleRequest } from "./handler.ts";

const updated = "2027-03-03T19:05:00Z";

Deno.test("Calendar feed serializes timed and off-legend shifts", () => {
  const result = calendar([
    {
      staff_member_id: "00000000-0000-0000-0000-000000000001",
      work_date: "2027-01-04",
      shift_code: "7P",
      starts_at: "2027-01-05T00:00:00Z",
      ends_at: "2027-01-05T12:00:00Z",
      updated_at: updated,
      sequence: 2,
    },
    {
      staff_member_id: "00000000-0000-0000-0000-000000000001",
      work_date: "2027-01-06",
      shift_code: "4P-8A, extra; shift",
      starts_at: null,
      ends_at: null,
      updated_at: updated,
      sequence: 0,
    },
  ], updated);
  if (!result.startsWith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n")) {
    throw new Error("Missing calendar header");
  }
  for (
    const line of [
      "DTSTART:20270105T000000Z\r\nDTEND:20270105T120000Z",
      "SUMMARY:Working — 4P-8A\\, extra\\; shift (time not set)",
      "SUMMARY:7P",
      "DTSTART;VALUE=DATE:20270106\r\nDTEND;VALUE=DATE:20270107",
      "DTSTAMP:20270303T190500Z",
      "LAST-MODIFIED:20270303T190500Z",
      "SEQUENCE:2",
      "X-PUBLISHED-TTL:PT15M",
      "REFRESH-INTERVAL;VALUE=DURATION:PT5M",
      "DESCRIPTION:Schedule as of Wed 3 Mar\\, 14:05.",
    ]
  ) {
    if (!result.includes(line)) throw new Error(`Missing ${line}`);
  }
  if (!result.endsWith("END:VCALENDAR\r\n")) {
    throw new Error("Missing calendar ending");
  }
});

Deno.test("Calendar feed cannot gain a property from a Shift code", () => {
  const result = calendar([{
    staff_member_id: "00000000-0000-0000-0000-000000000001",
    work_date: "2027-01-06",
    shift_code: "A\r\nDESCRIPTION:injected",
    starts_at: null,
    ends_at: null,
    updated_at: updated,
    sequence: 0,
  }], updated);
  if (!result.includes("SUMMARY:Working — A\\nDESCRIPTION:injected (time not set)")) {
    throw new Error("Shift code newline was not escaped");
  }
  if (result.includes("\r\nDESCRIPTION:injected")) {
    throw new Error("Shift code injected a calendar property");
  }
});

Deno.test("Calendar feed has stable validators and answers conditional GETs", async () => {
  const event = {
    staff_member_id: "00000000-0000-0000-0000-000000000001",
    work_date: "2027-03-04",
    shift_code: "7A",
    starts_at: null,
    ends_at: null,
    updated_at: updated,
    sequence: 1,
  };
  const request = (headers: HeadersInit = {}) =>
    new Request("https://example.test/feed", { headers });
  const first = await feedResponse(request(), [event], updated);
  const second = await feedResponse(request(), [event], updated);
  const etag = first.headers.get("ETag")!;
  if (first.status !== 200 || await first.text() !== await second.text() ||
    etag !== second.headers.get("ETag") ||
    first.headers.get("Last-Modified") !== "Wed, 03 Mar 2027 19:05:00 GMT") {
    throw new Error("Unchanged feed did not return stable content and validators");
  }
  const notModified = await feedResponse(request({ "If-None-Match": etag }), [event], updated);
  if (notModified.status !== 304 || await notModified.text() !== "" ||
    notModified.headers.get("ETag") !== etag) {
    throw new Error("Matching ETag did not return a bodyless 304");
  }
  const dateNotModified = await feedResponse(
    request({ "If-Modified-Since": "Wed, 03 Mar 2027 19:05:00 GMT" }), [event], updated,
  );
  if (dateNotModified.status !== 304) throw new Error("Matching date did not return 304");
  const changed = await feedResponse(request({ "If-None-Match": etag }),
    [{ ...event, sequence: 2, updated_at: "2027-03-03T19:06:00Z" }],
    "2027-03-03T19:06:00Z");
  if (changed.status !== 200 || changed.headers.get("ETag") === etag) {
    throw new Error("Changed feed was not returned");
  }
});

Deno.test("Empty feed has a Last-Modified validator", async () => {
  const timestamp = "2027-03-03T19:05:00Z";
  const first = await feedResponse(new Request("https://example.test/feed"), [], timestamp);
  const conditional = await feedResponse(new Request("https://example.test/feed", {
    headers: { "If-Modified-Since": first.headers.get("Last-Modified")! },
  }), [], timestamp);
  if (first.headers.get("Last-Modified") !== "Wed, 03 Mar 2027 19:05:00 GMT" ||
    conditional.status !== 304) {
    throw new Error("Empty feed did not honor its Last-Modified validator");
  }
});

const token = "a".repeat(64);
const revokedAt = "2027-03-03T02:05:00Z"; // Mar 2 in New York
const subscriptionId = "00000000-0000-0000-0000-000000000099";
const historyEvent = {
  staff_member_id: "00000000-0000-0000-0000-000000000001",
  work_date: "2027-03-02",
  shift_code: "7A",
  starts_at: null,
  ends_at: null,
  updated_at: updated,
  sequence: 1,
};

function feedState(state: "live" | "ended" | "feed" | "invitations", events = [historyEvent]) {
  return {
    state,
    subscription_id: subscriptionId,
    staff_member_id: historyEvent.staff_member_id,
    revoked_at: state === "live" ? null : revokedAt,
    last_modified: state === "live" ? updated : revokedAt,
    events,
  };
}

function request(headers: HeadersInit = {}) {
  return new Request(`https://example.test/calendar-feed/${token}`, { headers });
}

function unfolded(body: string) {
  return body.replaceAll("\r\n ", "");
}

Deno.test("Unknown Calendar feed token returns 404 after one state query", async () => {
  let calls = 0;
  const response = await handleRequest(request(), async (params) => {
    calls++;
    if (params.p_token !== token) throw new Error("Token was not passed to state query");
    return null;
  });
  if (response.status !== 404 || calls !== 1) throw new Error("Unknown token was not hidden");
});

Deno.test("Live Calendar feed keeps the existing bytes", async () => {
  const response = await handleRequest(request(), async () => feedState("live"));
  if (response.status !== 200 || await response.text() !== calendar([historyEvent], updated)) {
    throw new Error("Live feed changed its calendar body");
  }
});

Deno.test("Ended Calendar feed retains history silently, including the empty case", async () => {
  const response = await handleRequest(request(), async () => feedState("ended"));
  const body = unfolded(await response.text());
  if (response.status !== 200 || body.match(/BEGIN:VEVENT/g)?.length !== 1 ||
    !body.includes("DESCRIPTION:Schedule as of Tue 2 Mar\\, 21:05. This calendar is no longer updated.") ||
    body.includes("-disconnected@er-schedule") || body.includes("open the app")) {
    throw new Error("Ended feed did not quietly describe its frozen history");
  }
  const empty = await handleRequest(request(), async () => feedState("ended", []));
  const emptyBody = await empty.text();
  if (empty.status !== 200 || emptyBody.includes("BEGIN:VEVENT") ||
    !emptyBody.includes("BEGIN:VCALENDAR\r\n")) {
    throw new Error("Ended feed added a placeholder to empty history");
  }
});

for (const state of ["feed", "invitations"] as const) {
  Deno.test(`${state} Calendar feed shows a year-long disconnected banner`, async () => {
    const response = await handleRequest(request(), async () => feedState(state));
    const body = unfolded(await response.text());
    const banner = body.split("BEGIN:VEVENT\r\n")[1];
    const message = state === "feed"
      ? "The shifts below are your schedule as it stood that day. Open the app to set up a new link."
      : "Your shifts now arrive by email instead — you can delete this calendar.";
    if (response.status !== 200 || !banner.includes(`UID:${subscriptionId}-disconnected@er-schedule`) ||
      !banner.includes("DTSTART;VALUE=DATE:20270302") ||
      !banner.includes("DTEND;VALUE=DATE:20280302") ||
      !banner.includes("DTSTAMP:20270303T020500Z") ||
      !banner.includes("LAST-MODIFIED:20270303T020500Z") ||
      !banner.includes("SEQUENCE:0") ||
      !banner.includes("SUMMARY:ER Schedule: this calendar is no longer updated") ||
      !banner.includes(message) ||
      body.match(/BEGIN:VEVENT/g)?.length !== 2 ||
      response.headers.get("Last-Modified") !== "Wed, 03 Mar 2027 02:05:00 GMT") {
      throw new Error(`${state} feed did not show its stable disconnected banner`);
    }
  });
}

Deno.test("Disconnected Calendar feed repeats the same body and answers 304", async () => {
  const query = async () => feedState("feed");
  const first = await handleRequest(request(), query);
  const etag = first.headers.get("ETag")!;
  const body = await first.text();
  const second = await handleRequest(request({ "If-None-Match": etag }), query);
  const repeated = await handleRequest(request(), query);
  if (second.status !== 304 || await second.text() !== "" ||
    body !== await repeated.text() || etag !== repeated.headers.get("ETag")) {
    throw new Error("Disconnected feed changed between fetches");
  }
});
