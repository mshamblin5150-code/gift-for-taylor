import { calendar } from "./calendar.ts";

Deno.test("Calendar feed serializes timed and off-legend shifts", () => {
  const result = calendar([
    {
      staff_member_id: "00000000-0000-0000-0000-000000000001",
      work_date: "2027-01-04",
      shift_code: "7P",
      starts_at: "2027-01-05T00:00:00Z",
      ends_at: "2027-01-05T12:00:00Z",
    },
    {
      staff_member_id: "00000000-0000-0000-0000-000000000001",
      work_date: "2027-01-06",
      shift_code: "4P-8A, extra; shift",
      starts_at: null,
      ends_at: null,
    },
  ]);
  if (!result.startsWith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n")) {
    throw new Error("Missing calendar header");
  }
  for (
    const line of [
      "DTSTART:20270105T000000Z\r\nDTEND:20270105T120000Z",
      "SUMMARY:4P-8A\\, extra\\; shift",
      "DTSTART;VALUE=DATE:20270106\r\nDTEND;VALUE=DATE:20270107",
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
  }]);
  if (!result.includes("SUMMARY:A\\nDESCRIPTION:injected")) {
    throw new Error("Shift code newline was not escaped");
  }
  if (result.includes("\r\nDESCRIPTION:injected")) {
    throw new Error("Shift code injected a calendar property");
  }
});
