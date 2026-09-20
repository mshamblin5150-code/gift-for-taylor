import { shiftSummary } from "../_shared/shift_summary.ts";

export type Invitation = {
  id: string;
  staff_member_id: string;
  work_date: string;
  recipient: string;
  method: "REQUEST" | "CANCEL";
  shift_code: string;
  starts_at: string | null;
  ends_at: string | null;
  sequence: number;
  last_modified: string;
};

export const sender = "no-reply@axion.healthcare";

function text(value: string): string {
  return value.replaceAll(/\r\n?/g, "\n").replaceAll("\\", "\\\\")
    .replaceAll("\n", "\\n").replaceAll(",", "\\,")
    .replaceAll(";", "\\;");
}

function fold(line: string): string {
  let result = "";
  let length = 0;
  for (const character of line) {
    const bytes = new TextEncoder().encode(character).length;
    if (length + bytes > 75) {
      result += "\r\n ";
      length = 1;
    }
    result += character;
    length += bytes;
  }
  return result;
}

function stamp(value: string): string {
  return new Date(value).toISOString().replaceAll(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
}

function nextDay(date: string): string {
  const day = new Date(`${date}T00:00:00Z`);
  day.setUTCDate(day.getUTCDate() + 1);
  return day.toISOString().slice(0, 10).replaceAll("-", "");
}

export function invitationCalendar(event: Invitation): string {
  const date = event.work_date.replaceAll("-", "");
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//ER Schedule//Calendar Invitation//EN",
    "CALSCALE:GREGORIAN",
    `METHOD:${event.method}`,
    "BEGIN:VEVENT",
    `UID:${event.staff_member_id}-${date}@er-schedule`,
    `DTSTAMP:${stamp(event.last_modified)}`,
    `LAST-MODIFIED:${stamp(event.last_modified)}`,
    `SEQUENCE:${event.sequence}`,
    `ORGANIZER;CN=ER Schedule:mailto:${sender}`,
    `ATTENDEE;RSVP=FALSE;PARTSTAT=ACCEPTED:mailto:${event.recipient}`,
    `SUMMARY:${text(shiftSummary(event.shift_code, event.starts_at, event.ends_at))}`,
  ];
  if (event.method === "CANCEL") lines.push("STATUS:CANCELLED");
  if (event.starts_at && event.ends_at) {
    lines.push(`DTSTART:${stamp(event.starts_at)}`,
      `DTEND:${stamp(event.ends_at)}`);
  } else {
    lines.push(`DTSTART;VALUE=DATE:${date}`,
      `DTEND;VALUE=DATE:${nextDay(event.work_date)}`);
  }
  lines.push("END:VEVENT", "END:VCALENDAR");
  return `${lines.map(fold).join("\r\n")}\r\n`;
}

export function invitationMessage(event: Invitation) {
  const summary = shiftSummary(event.shift_code, event.starts_at, event.ends_at);
  return {
    from: `ER Schedule <${sender}>`,
    to: event.recipient,
    subject: event.method === "CANCEL"
      ? `Shift removed: ${event.work_date}`
      : `${summary} — ${event.work_date}`,
    text: event.method === "CANCEL"
      ? `Your ${event.work_date} shift was removed from the Schedule. The attached calendar event withdraws it. Check the app for the current Schedule.`
      : `Your ${event.work_date} shift is ${summary}. The attached calendar event keeps your calendar in sync. Check the app for the current Schedule. No reply is needed.`,
    icalEvent: { method: event.method, content: invitationCalendar(event),
      filename: "schedule-shift.ics" },
  };
}
