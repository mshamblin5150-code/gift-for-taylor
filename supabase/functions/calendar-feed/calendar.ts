export type FeedEvent = {
  staff_member_id: string;
  work_date: string;
  shift_code: string;
  starts_at: string | null;
  ends_at: string | null;
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

export function calendar(events: FeedEvent[]): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//ER Schedule//Calendar Feed//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:My Schedule",
  ];
  for (const event of events) {
    const date = event.work_date.replaceAll("-", "");
    lines.push(
      "BEGIN:VEVENT",
      `UID:${event.staff_member_id}-${date}@er-schedule`,
      `DTSTAMP:${utcStamp(new Date().toISOString())}`,
      `SUMMARY:${escapeText(event.shift_code)}`,
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
