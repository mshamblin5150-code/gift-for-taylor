import {
  createCalendarInvitationHandler,
  type DeliveryDependencies,
} from "./delivery.ts";
import type { Invitation } from "./calendar.ts";

const invitation = (id: string): Invitation & { delivery_claim: string } => ({
  id,
  delivery_claim: `claim-${id}`,
  staff_member_id: "00000000-0000-0000-0000-000000000001",
  work_date: "2027-01-04",
  recipient: "staff@example.test",
  method: "REQUEST",
  shift_code: "7A",
  starts_at: "2027-01-04T12:00:00Z",
  ends_at: "2027-01-05T00:00:00Z",
  sequence: 0,
  last_modified: "2026-12-01T10:01:02Z",
});

function request(id: string): Request {
  return new Request("https://example.test/send-calendar-invitation", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-calendar-secret": "secret",
    },
    body: JSON.stringify({ id }),
  });
}

Deno.test("a burst sends each queued invitation exactly once", async () => {
  const queued = new Map(
    ["one", "two", "three"].map((id) => [id, invitation(id)]),
  );
  const claimed = new Set<string>();
  const sends: string[] = [];
  const dependencies: DeliveryDependencies = {
    secret: "secret",
    claim: (id) => {
      const event = queued.get(id);
      if (!event || claimed.has(id)) return Promise.resolve(null);
      claimed.add(id);
      return Promise.resolve(event);
    },
    send: (event) => {
      sends.push(event.id);
      return Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    release: () => Promise.resolve(),
  };
  const handler = createCalendarInvitationHandler(dependencies);

  const responses = await Promise.all(
    [...queued.keys()].map((id) => handler(request(id))),
  );

  if (responses.some((response) => response.status !== 200)) {
    throw new Error("A queued invitation did not report success");
  }
  if (sends.join(",") !== "one,two,three") {
    throw new Error(`Expected one send per row, got ${sends.join(",")}`);
  }
});

Deno.test("concurrent invocations cannot send the same invitation twice", async () => {
  const event = invitation("same-row");
  let claimed = false;
  let sends = 0;
  const dependencies: DeliveryDependencies = {
    secret: "secret",
    claim: () => {
      if (claimed) return Promise.resolve(null);
      claimed = true;
      return Promise.resolve(event);
    },
    send: async () => {
      sends++;
      await Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    release: () => Promise.resolve(),
  };
  const handler = createCalendarInvitationHandler(dependencies);

  const responses = await Promise.all([
    handler(request(event.id)),
    handler(request(event.id)),
  ]);

  if (sends !== 1) throw new Error(`Expected one send, got ${sends}`);
  if (responses.filter((response) => response.status === 200).length !== 2) {
    throw new Error("Concurrent invocations were not handled idempotently");
  }
});

Deno.test("a failed send releases only its claimed invitation for retry", async () => {
  const event = invitation("failed-row");
  const releases: Array<[string, string]> = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve(event),
    send: () => Promise.reject(new Error("provider unavailable")),
    markSent: () => Promise.resolve(),
    release: (id, claim) => {
      releases.push([id, claim]);
      return Promise.resolve();
    },
  });

  const response = await handler(request(event.id));

  if (response.status !== 502) {
    throw new Error(`Expected provider failure, got ${response.status}`);
  }
  if (
    JSON.stringify(releases) !==
      JSON.stringify([[event.id, event.delivery_claim]])
  ) {
    throw new Error(`Unexpected claim releases: ${JSON.stringify(releases)}`);
  }
});
