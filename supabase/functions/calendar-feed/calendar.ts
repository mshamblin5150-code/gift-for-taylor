import { shiftSummary } from "../_shared/shift_summary.ts";

export type FeedEvent = {
  staff_member_id: string;
  work_date: string;
  shift_code: string;
  starts_at: string | null;
  ends_at: string | null;
  updated_at: string;
  sequence: number;
};

export type DisconnectedFeed = {
  state: "ended" | "feed" | "invitations";
  subscriptionId: string;
  revokedAt: string;
};

function escapeText(value: string): string {
  return value.replaceAll(/\r\n?/g, "\n").replaceAll("\\", "\\\\")
    .replaceAll("\n", "\\n")
    .replaceAll(",", "\\,").replaceAll(";", "\\;");
}

function foldLine(line: string): string {
  const encoder = new TextEncoder();
  let result = "";
  let length = 0;
  for (const character of line) {
    const bytes = encoder.encode(character).length;
    if (length + bytes > 75) {
      result += "\r\n ";
      length = 1;
    }
    result += character;
    length += bytes;
  }
  return result;
}

function utcStamp(value: string): string {
  return new Date(value).toISOString().replaceAll(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
}

function nextDay(date: string): string {
  const day = new Date(`${date}T00:00:00Z`);
  day.setUTCDate(day.getUTCDate() + 1);
  return day.toISOString().slice(0, 10).replaceAll("-", "");
}

function scheduleAsOf(value: string): string {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York", weekday: "short", day: "numeric",
    month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(new Date(value));
  const part = (type: string) => parts.find((item) => item.type === type)?.value;
  return `${part("weekday")} ${part("day")} ${part("month")}, ${part("hour")}:${part("minute")}`;
}

export function calendar(
  events: FeedEvent[], feedUpdatedAt: string | null,
  disconnected?: DisconnectedFeed,
): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//ER Schedule//Calendar Feed//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:My Schedule",
    "X-PUBLISHED-TTL:PT15M",
    "REFRESH-INTERVAL;VALUE=DURATION:PT5M",
  ];
  const stamp = feedUpdatedAt ?? "1970-01-01T00:00:00Z";
  if (disconnected && disconnected.state !== "ended") {
    const dateParts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(new Date(disconnected.revokedAt));
    const part = (type: string) => dateParts.find((item) => item.type === type)?.value;
    const localDate = `${part("year")}-${part("month")}-${part("day")}`;
    const start = localDate.replaceAll("-", "");
    const endDate = new Date(`${localDate}T00:00:00Z`);
    const startMonth = endDate.getUTCMonth();
    endDate.setUTCFullYear(endDate.getUTCFullYear() + 1);
    if (endDate.getUTCMonth() !== startMonth) endDate.setUTCDate(0);
    const end = endDate.toISOString().slice(0, 10).replaceAll("-", "");
    const explanation = disconnected.state === "feed"
      ? `This calendar link was disconnected on ${scheduleAsOf(disconnected.revokedAt)}. The shifts below are your schedule as it stood that day. Open the app to set up a new link.`
      : `This calendar link was disconnected on ${scheduleAsOf(disconnected.revokedAt)}. Your shifts now arrive by email instead — you can delete this calendar.`;
    lines.push(
      "BEGIN:VEVENT",
      `UID:${disconnected.subscriptionId}-disconnected@er-schedule`,
      `DTSTAMP:${utcStamp(disconnected.revokedAt)}`,
      `LAST-MODIFIED:${utcStamp(disconnected.revokedAt)}`,
      "SEQUENCE:0",
      `DTSTART;VALUE=DATE:${start}`,
      `DTEND;VALUE=DATE:${end}`,
      "SUMMARY:ER Schedule: this calendar is no longer updated",
      `DESCRIPTION:${escapeText(explanation)}`,
      "END:VEVENT",
    );
  }
  for (const event of events) {
    const date = event.work_date.replaceAll("-", "");
    lines.push(
      "BEGIN:VEVENT",
      `UID:${event.staff_member_id}-${date}@er-schedule`,
      `DTSTAMP:${utcStamp(stamp)}`,
      `LAST-MODIFIED:${utcStamp(event.updated_at)}`,
      `SEQUENCE:${event.sequence}`,
      `SUMMARY:${escapeText(shiftSummary(event.shift_code, event.starts_at, event.ends_at))}`,
      `DESCRIPTION:${escapeText(disconnected
        ? `Schedule as of ${scheduleAsOf(disconnected.revokedAt)}. This calendar is no longer updated.`
        : `Schedule as of ${scheduleAsOf(stamp)}. Your calendar refreshes on its own schedule; open the app if this matters.`)}`,
    );
    if (event.starts_at && event.ends_at) {
      lines.push(
        `DTSTART:${utcStamp(event.starts_at)}`,
        `DTEND:${utcStamp(event.ends_at)}`,
      );
    } else {
      lines.push(
        `DTSTART;VALUE=DATE:${date}`,
        `DTEND;VALUE=DATE:${nextDay(event.work_date)}`,
      );
    }
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return `${lines.map(foldLine).join("\r\n")}\r\n`;
}
