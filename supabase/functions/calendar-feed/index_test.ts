import { calendar } from "./calendar.ts";
import { feedResponse } from "./response.ts";

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
      "SUMMARY:4P-8A\\, extra\\; shift",
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
  if (!result.includes("SUMMARY:A\\nDESCRIPTION:injected")) {
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
