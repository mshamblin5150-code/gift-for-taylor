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
      const queuedInvitation = queued.get(id);
      if (!queuedInvitation || claimed.has(id)) return Promise.resolve([]);
      claimed.add(id);
      return Promise.resolve([queuedInvitation]);
    },
    beginSend: (invitations) => Promise.resolve(invitations),
    send: (queuedInvitations) => {
      sends.push(queuedInvitations[0].id);
      return Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    markFailed: () => Promise.resolve(),
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

Deno.test("a Month release sends one message per recipient", async () => {
  const first = { ...invitation("first-shift"), batch_id: "release-batch" };
  const second = {
    ...invitation("second-shift"),
    batch_id: "release-batch",
    work_date: "2027-01-05",
  };
  const otherStaff = {
    ...invitation("other-staff-shift"),
    batch_id: "release-batch",
    staff_member_id: "00000000-0000-0000-0000-000000000002",
    recipient: "other@example.test",
  };
  const messages: string[][] = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([first, second, otherStaff]),
    beginSend: (invitations) => Promise.resolve(invitations),
    send: (events) => {
      messages.push(events.map((event) => event.id));
      return Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    markFailed: () => Promise.resolve(),
    release: () => Promise.resolve(),
  });

  const response = await handler(request("release-batch"));

  if (response.status !== 200) throw new Error("Release delivery failed");
  if (messages.length !== 2) {
    throw new Error(`Expected two messages, got ${messages.length}`);
  }
  if (messages[0].join(",") !== "first-shift,second-shift") {
    throw new Error(`First recipient shifts were split: ${messages[0]}`);
  }
  if (messages[1].join(",") !== "other-staff-shift") {
    throw new Error(`Other recipient was not isolated: ${messages[1]}`);
  }
});

Deno.test("a calendar message never mixes REQUEST and CANCEL", async () => {
  const methods: string[][] = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () =>
      Promise.resolve([
        invitation("requested-shift"),
        { ...invitation("cancelled-shift"), method: "CANCEL" },
      ]),
    beginSend: (invitations) => Promise.resolve(invitations),
    send: (events) => {
      methods.push(events.map((event) => event.method));
      return Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    markFailed: () => Promise.resolve(),
    release: () => Promise.resolve(),
  });

  await handler(request("mixed-batch"));

  if (JSON.stringify(methods) !== JSON.stringify([["REQUEST"], ["CANCEL"]])) {
    throw new Error(`Methods were mixed in one message: ${methods}`);
  }
});

Deno.test("a superseded claimed shift is removed before sending", async () => {
  const first = invitation("superseded-shift");
  const second = {
    ...invitation("current-shift"),
    work_date: "2027-01-05",
  };
  const sends: string[][] = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([first, second]),
    beginSend: (events) => Promise.resolve([events[1]]),
    send: (events) => {
      sends.push(events.map((event) => event.id));
      return Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    markFailed: () => Promise.resolve(),
    release: () => Promise.resolve(),
  });

  await handler(request("release-batch"));

  if (JSON.stringify(sends) !== JSON.stringify([["current-shift"]])) {
    throw new Error(`Superseded shift reached SMTP: ${JSON.stringify(sends)}`);
  }
});

Deno.test("an uncertain recipient does not block later recipients", async () => {
  const first = invitation("uncertain-recipient");
  const second = {
    ...invitation("later-recipient"),
    staff_member_id: "00000000-0000-0000-0000-000000000002",
    recipient: "later@example.test",
  };
  const attempts: string[] = [];
  const completed: string[] = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([first, second]),
    beginSend: (events) => Promise.resolve(events),
    send: (events) => {
      attempts.push(events[0].recipient);
      return events[0].recipient === first.recipient
        ? Promise.reject(new Error("connection lost after DATA"))
        : Promise.resolve();
    },
    markSent: (events) => {
      completed.push(events[0].recipient);
      return Promise.resolve();
    },
    markFailed: () => Promise.resolve(),
    release: () => Promise.resolve(),
  });

  const response = await handler(request("release-batch"));

  if (response.status !== 502) {
    throw new Error(`Expected 502, got ${response.status}`);
  }
  if (attempts.join(",") !== "staff@example.test,later@example.test") {
    throw new Error(`Later recipient was blocked: ${attempts}`);
  }
  if (completed.join(",") !== "later@example.test") {
    throw new Error(`Later recipient was not completed: ${completed}`);
  }
});

Deno.test("concurrent invocations cannot send the same invitation twice", async () => {
  const claimedInvitation = invitation("same-row");
  let claimed = false;
  let sends = 0;
  const dependencies: DeliveryDependencies = {
    secret: "secret",
    claim: () => {
      if (claimed) return Promise.resolve([]);
      claimed = true;
      return Promise.resolve([claimedInvitation]);
    },
    beginSend: (invitations) => Promise.resolve(invitations),
    send: async () => {
      sends++;
      await Promise.resolve();
    },
    markSent: () => Promise.resolve(),
    markFailed: () => Promise.resolve(),
    release: () => Promise.resolve(),
  };
  const handler = createCalendarInvitationHandler(dependencies);

  const responses = await Promise.all([
    handler(request(claimedInvitation.id)),
    handler(request(claimedInvitation.id)),
  ]);

  if (sends !== 1) throw new Error(`Expected one send, got ${sends}`);
  if (responses.filter((response) => response.status === 200).length !== 2) {
    throw new Error("Concurrent invocations were not handled idempotently");
  }
});

Deno.test("a refused send records an outcome before its atomic release", async () => {
  const claimedInvitation = invitation("failed-row");
  const releases: Array<[string, string]> = [];
  const failures: Array<[string, string | null, string | null, string]> = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([claimedInvitation]),
    beginSend: (invitations) => Promise.resolve(invitations),
    send: () =>
      Promise.reject(Object.assign(new Error("quota reached"), {
        code: "EENVELOPE",
        responseCode: 550,
      })),
    markSent: () => Promise.resolve(),
    markFailed: (_invitations, failure) => {
      failures.push([
        failure.outcome,
        failure.code,
        failure.statusCode,
        failure.message,
      ]);
      return Promise.resolve();
    },
    release: (invitations) => {
      releases.push([invitations[0].id, invitations[0].delivery_claim]);
      return Promise.resolve();
    },
  });

  const response = await handler(request(claimedInvitation.id));

  if (response.status !== 502) {
    throw new Error(`Expected provider failure, got ${response.status}`);
  }
  if (releases.length !== 0) throw new Error("Refusal was released twice");
  if (
    JSON.stringify(failures) !==
      JSON.stringify([["refused", "EENVELOPE", "550", "quota reached"]])
  ) {
    throw new Error(
      `Provider reply was not recorded: ${JSON.stringify(failures)}`,
    );
  }
});

Deno.test("an ambiguous SMTP failure is held instead of released", async () => {
  const claimedInvitation = invitation("ambiguous-row");
  let released = false;
  let recorded = false;
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([claimedInvitation]),
    beginSend: (invitations) => Promise.resolve(invitations),
    send: () => Promise.reject(new Error("connection lost after DATA")),
    markSent: () => Promise.resolve(),
    markFailed: (_invitations, failure) => {
      recorded = failure.outcome === "uncertain" &&
        failure.message === "connection lost after DATA";
      return Promise.resolve();
    },
    release: () => {
      released = true;
      return Promise.resolve();
    },
  });

  const response = await handler(request(claimedInvitation.id));

  if (response.status !== 502) {
    throw new Error(`Expected SMTP failure, got ${response.status}`);
  }
  if (released) {
    throw new Error("Ambiguous SMTP outcome was released for retry");
  }
  if (!recorded) throw new Error("Ambiguous SMTP outcome was not recorded");
});

Deno.test("a failure that cannot be recorded is held", async () => {
  const claimedInvitation = invitation("unrecorded-row");
  let released = false;
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([claimedInvitation]),
    beginSend: (invitations) => Promise.resolve(invitations),
    send: () =>
      Promise.reject(Object.assign(new Error("quota reached"), {
        responseCode: 550,
      })),
    markSent: () => Promise.resolve(),
    markFailed: () => Promise.reject(new Error("database unavailable")),
    release: () => {
      released = true;
      return Promise.resolve();
    },
  });

  const response = await handler(request(claimedInvitation.id));

  if (response.status !== 503) {
    throw new Error(`Expected recording failure, got ${response.status}`);
  }
  if (released) throw new Error("An unrecorded failure was released");
});

Deno.test("an uncertain completed send is held instead of released", async () => {
  const claimedInvitation = invitation("uncertain-row");
  const steps: string[] = [];
  const handler = createCalendarInvitationHandler({
    secret: "secret",
    claim: () => Promise.resolve([claimedInvitation]),
    beginSend: (invitations) => {
      steps.push("begin");
      return Promise.resolve(invitations);
    },
    send: () => {
      steps.push("send");
      return Promise.resolve();
    },
    markSent: () => {
      steps.push("mark");
      return Promise.reject(new Error("database unavailable"));
    },
    markFailed: () => Promise.resolve(),
    release: () => {
      steps.push("release");
      return Promise.resolve();
    },
  });

  const response = await handler(request(claimedInvitation.id));

  if (response.status !== 503) {
    throw new Error(`Expected completion failure, got ${response.status}`);
  }
  if (steps.join(",") !== "begin,send,mark") {
    throw new Error(`Uncertain send was released: ${steps.join(",")}`);
  }
});
