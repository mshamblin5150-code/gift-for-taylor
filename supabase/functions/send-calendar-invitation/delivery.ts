import type { Invitation } from "./calendar.ts";

export type ClaimedInvitation = Invitation & { delivery_claim: string };

export type DeliveryDependencies = {
  secret: string;
  claim: (id: string) => Promise<ClaimedInvitation | null>;
  beginSend: (invitation: ClaimedInvitation) => Promise<void>;
  send: (invitation: ClaimedInvitation) => Promise<void>;
  markSent: (invitation: ClaimedInvitation) => Promise<void>;
  release: (invitation: ClaimedInvitation) => Promise<void>;
};

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status });
}

export function isCalendarInvitationRequestAuthorized(
  request: Request,
  secret: string | null | undefined,
): secret is string {
  return Boolean(secret) && request.method === "POST" &&
    request.headers.get("x-calendar-secret") === secret;
}

function isDefinitiveSmtpRejection(error: unknown): boolean {
  if (
    typeof error !== "object" || error === null || !("responseCode" in error)
  ) {
    return false;
  }
  const responseCode = (error as { responseCode?: unknown }).responseCode;
  return typeof responseCode === "number" && responseCode >= 400 &&
    responseCode <= 599;
}

export function createCalendarInvitationHandler(
  dependencies: DeliveryDependencies,
): (request: Request) => Promise<Response> {
  async function releaseForRetry(invitation: ClaimedInvitation): Promise<void> {
    try {
      await dependencies.release(invitation);
    } catch (releaseError) {
      console.error(
        "Calendar invitation claim release failed",
        invitation.id,
        releaseError,
      );
    }
  }

  return async (request) => {
    if (!isCalendarInvitationRequestAuthorized(request, dependencies.secret)) {
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

    let invitation: ClaimedInvitation | null;
    try {
      invitation = await dependencies.claim(id);
    } catch (error) {
      console.error("Calendar invitation claim failed", id, error);
      return json({ sent: 0, failures: 1 }, 503);
    }
    if (!invitation) return json({ sent: 0, failures: 0 });

    try {
      await dependencies.beginSend(invitation);
    } catch (error) {
      console.error("Calendar invitation send start failed", id, error);
      await releaseForRetry(invitation);
      return json({ sent: 0, failures: 1 }, 503);
    }

    try {
      await dependencies.send(invitation);
    } catch (error) {
      console.error("Calendar invitation delivery failed", id, error);
      if (isDefinitiveSmtpRejection(error)) await releaseForRetry(invitation);
      return json({ sent: 0, failures: 1 }, 502);
    }

    try {
      await dependencies.markSent(invitation);
    } catch (error) {
      console.error("Calendar invitation completion failed", id, error);
      return json({ sent: 0, failures: 1 }, 503);
    }
    return json({ sent: 1, failures: 0 });
  };
}
