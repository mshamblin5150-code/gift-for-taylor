import nodemailer from "npm:nodemailer@7.0.6";
import {
  type Invitation,
  invitationCalendar,
  invitationMessage,
} from "./calendar.ts";

const shift: Invitation = {
  id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  staff_member_id: "00000000-0000-0000-0000-000000000001",
  work_date: "2027-01-04",
  recipient: "staff@example.test",
  method: "REQUEST",
  shift_code: "7A",
  starts_at: "2027-01-04T12:00:00Z",
  ends_at: "2027-01-05T00:00:00Z",
  sequence: 0,
  last_modified: "2026-12-01T10:01:02Z",
};

Deno.test("Calendar invitation requests a shift without asking for a reply", () => {
  const result = invitationCalendar(shift);
  for (
    const line of [
      "METHOD:REQUEST",
      "UID:00000000-0000-0000-0000-000000000001-20270104@er-schedule",
      "SEQUENCE:0",
      "LAST-MODIFIED:20261201T100102Z",
      "ORGANIZER;CN=ER Schedule:mailto:no-reply@axion.healthcare",
      "ATTENDEE;RSVP=FALSE;PARTSTAT=ACCEPTED:mailto:staff@example.test",
      "SUMMARY:7A",
      "DTSTART:20270104T120000Z",
      "DTEND:20270105T000000Z",
    ]
  ) {
    if (!result.includes(`${line}\r\n`)) throw new Error(`Missing ${line}`);
  }
});

Deno.test("Untimed working shift remains visible with an honest title", () => {
  const untimed = {
    ...shift,
    shift_code: "9-7",
    starts_at: null,
    ends_at: null,
  };
  const result = invitationCalendar(untimed);
  if (
    !result.includes("SUMMARY:Working — 9-7 (time not set)\r\n") ||
    !result.includes("DTSTART;VALUE=DATE:20270104\r\n") ||
    !result.includes("DTEND;VALUE=DATE:20270105\r\n")
  ) {
    throw new Error("Untimed shift was not shown as a labeled all-day event");
  }
  const message = invitationMessage(untimed);
  if (
    !message.subject.includes("Working — 9-7 (time not set)") ||
    !message.text.includes("Working — 9-7 (time not set)")
  ) {
    throw new Error("Invitation email omitted the unknown time");
  }
});

Deno.test("Cancellation retains the event identity and advances its sequence", () => {
  const result = invitationCalendar({
    ...shift,
    method: "CANCEL",
    sequence: 1,
    last_modified: "2026-12-02T10:01:02Z",
  });
  if (
    !result.includes("METHOD:CANCEL\r\n") ||
    !result.includes("STATUS:CANCELLED\r\n") ||
    !result.includes("SEQUENCE:1\r\n") ||
    !result.includes("LAST-MODIFIED:20261202T100102Z\r\n")
  ) {
    throw new Error("Cancellation is missing iMIP update fields");
  }
});

Deno.test("Shift code cannot inject a calendar property", () => {
  const result = invitationCalendar({
    ...shift,
    shift_code: "7A\r\nMETHOD:PUBLISH",
  });
  if (
    !result.includes("SUMMARY:7A\\nMETHOD:PUBLISH") ||
    result.includes("\r\nMETHOD:PUBLISH\r\n")
  ) {
    throw new Error("Shift code escaped the SUMMARY field");
  }
});

Deno.test("Email carries an iMIP request rather than a calendar import", async () => {
  const transport = nodemailer.createTransport({
    streamTransport: true,
    buffer: true,
  });
  const result = await transport.sendMail(invitationMessage(shift));
  const raw = result.message.toString();
  if (
    !raw.includes("Content-Type: text/calendar; charset=utf-8; method=REQUEST")
  ) {
    throw new Error("Email lacks a calendar REQUEST MIME part");
  }
  if (!raw.includes("From: ER Schedule <no-reply@axion.healthcare>")) {
    throw new Error("Email sender is not the no-reply app identity");
  }
  const cancelled = await transport.sendMail(invitationMessage({
    ...shift,
    method: "CANCEL",
    sequence: 1,
  }));
  if (
    !cancelled.message.toString().includes(
      "Content-Type: text/calendar; charset=utf-8; method=CANCEL",
    )
  ) {
    throw new Error("Email lacks a calendar CANCEL MIME part");
  }
});

Deno.test("Month release carries several shifts in one calendar message", async () => {
  const nextShift: Invitation = {
    ...shift,
    id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    work_date: "2027-01-05",
    starts_at: "2027-01-05T12:00:00Z",
    ends_at: "2027-01-06T00:00:00Z",
  };
  const transport = nodemailer.createTransport({
    streamTransport: true,
    buffer: true,
  });

  const result = await transport.sendMail(
    invitationMessage([shift, nextShift]),
  );
  const raw = result.message.toString();

  if ((raw.match(/METHOD:REQUEST/g) ?? []).length !== 1) {
    throw new Error("A batched invitation must carry exactly one METHOD");
  }
  if ((raw.match(/BEGIN:VEVENT/g) ?? []).length !== 2) {
    throw new Error("A batched invitation must carry one VEVENT per shift");
  }
  for (
    const uid of [
      "00000000-0000-0000-0000-000000000001-20270104@er-schedule",
      "00000000-0000-0000-0000-000000000001-20270105@er-schedule",
    ]
  ) {
    if (!raw.includes(`UID:${uid}`)) throw new Error(`Missing ${uid}`);
  }
});
