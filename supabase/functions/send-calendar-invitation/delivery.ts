import type { Invitation } from "./calendar.ts";

export type ClaimedInvitation = Invitation & { delivery_claim: string };

export type DeliveryDependencies = {
  secret: string;
  claim: (id: string) => Promise<ClaimedInvitation | null>;
  send: (event: ClaimedInvitation) => Promise<void>;
  markSent: (id: string, claim: string) => Promise<void>;
  release: (id: string, claim: string) => Promise<void>;
};

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status });
}

export function createCalendarInvitationHandler(
  dependencies: DeliveryDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (
      request.method !== "POST" ||
      request.headers.get("x-calendar-secret") !== dependencies.secret
    ) {
      return new Response("Unauthorized", { status: 401 });
    }

    let id: unknown;
    try {
      id = (await request.json()).id;
    } catch {
      return new Response("Invalid invitation id", { status: 400 });
    }
    if (typeof id !== "string" || id.length === 0) {
      return new Response("Invalid invitation id", { status: 400 });
    }

    let event: ClaimedInvitation | null;
    try {
      event = await dependencies.claim(id);
    } catch (error) {
      console.error("Calendar invitation claim failed", id, error);
      return json({ sent: 0, failures: 1 }, 503);
    }
    if (!event) return json({ sent: 0, failures: 0 });

    try {
      await dependencies.send(event);
    } catch (error) {
      console.error("Calendar invitation delivery failed", id, error);
      try {
        await dependencies.release(id, event.delivery_claim);
      } catch (releaseError) {
        console.error(
          "Calendar invitation claim release failed",
          id,
          releaseError,
        );
      }
      return json({ sent: 0, failures: 1 }, 502);
    }

    try {
      await dependencies.markSent(id, event.delivery_claim);
    } catch (error) {
      console.error("Calendar invitation completion failed", id, error);
      return json({ sent: 0, failures: 1 }, 503);
    }
    return json({ sent: 1, failures: 0 });
  };
}
