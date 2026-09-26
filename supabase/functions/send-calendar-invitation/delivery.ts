import type { Invitation } from "./calendar.ts";

export type ClaimedInvitation = Invitation & { delivery_claim: string };

export type ClaimedInvitationMessage = readonly ClaimedInvitation[];

export type DeliveryFailure = {
  outcome: "refused" | "uncertain";
  code: string | null;
  statusCode: string | null;
  message: string;
};

export type DeliveryDependencies = {
  secret: string;
  claim: (id: string) => Promise<ClaimedInvitationMessage>;
  beginSend: (
    invitations: ClaimedInvitationMessage,
  ) => Promise<ClaimedInvitationMessage>;
  send: (invitations: ClaimedInvitationMessage) => Promise<void>;
  markSent: (invitations: ClaimedInvitationMessage) => Promise<void>;
  markFailed: (
    invitations: ClaimedInvitationMessage,
    failure: DeliveryFailure,
  ) => Promise<void>;
  release: (invitations: ClaimedInvitationMessage) => Promise<void>;
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

function deliveryFailure(
  error: unknown,
  outcome: DeliveryFailure["outcome"],
): DeliveryFailure {
  if (typeof error !== "object" || error === null) {
    return { outcome, code: null, statusCode: null, message: String(error) };
  }
  const smtpError = error as {
    code?: unknown;
    responseCode?: unknown;
    response?: unknown;
    message?: unknown;
  };
  return {
    outcome,
    code: typeof smtpError.code === "string" ? smtpError.code : null,
    statusCode: typeof smtpError.responseCode === "number"
      ? String(smtpError.responseCode)
      : null,
    message: typeof smtpError.response === "string" && smtpError.response.length
      ? smtpError.response
      : typeof smtpError.message === "string" && smtpError.message.length
      ? smtpError.message
      : "Unknown provider failure",
  };
}

export function createCalendarInvitationHandler(
  dependencies: DeliveryDependencies,
): (request: Request) => Promise<Response> {
  async function releaseForRetry(
    invitations: ClaimedInvitationMessage,
  ): Promise<void> {
    try {
      await dependencies.release(invitations);
    } catch (releaseError) {
      console.error(
        "Calendar invitation claim release failed",
        invitations[0]?.id,
        releaseError,
      );
    }
  }

  function groupClaimsForDelivery(
    invitations: ClaimedInvitationMessage,
  ): ClaimedInvitationMessage[] {
    const grouped = new Map<
      string,
      Map<Invitation["method"], ClaimedInvitation[]>
    >();
    for (const invitation of invitations) {
      const recipientGroups = grouped.get(invitation.recipient) ?? new Map();
      const group = recipientGroups.get(invitation.method) ?? [];
      group.push(invitation);
      recipientGroups.set(invitation.method, group);
      grouped.set(invitation.recipient, recipientGroups);
    }
    return [...grouped.values()].flatMap((recipientGroups) =>
      [...recipientGroups.values()].map((group) =>
        group.sort((left, right) =>
          left.work_date.localeCompare(right.work_date)
        )
      )
    );
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

    let invitations: ClaimedInvitationMessage;
    try {
      invitations = await dependencies.claim(id);
    } catch (error) {
      console.error("Calendar invitation claim failed", id, error);
      return json({ sent: 0, failures: 1 }, 503);
    }
    if (invitations.length === 0) return json({ sent: 0, failures: 0 });

    const queuedMessages = groupClaimsForDelivery(invitations);
    let sent = 0;
    let failures = 0;
    let failureStatus = 200;
    for (let index = 0; index < queuedMessages.length; index++) {
      const message = queuedMessages[index];
      let sendable: ClaimedInvitationMessage;
      try {
        sendable = await dependencies.beginSend(message);
      } catch (error) {
        console.error("Calendar invitation send start failed", id, error);
        await releaseForRetry(message);
        failures++;
        failureStatus = 503;
        continue;
      }
      if (sendable.length === 0) continue;

      try {
        await dependencies.send(sendable);
      } catch (error) {
        console.error("Calendar invitation delivery failed", id, error);
        const refused = isDefinitiveSmtpRejection(error);
        try {
          await dependencies.markFailed(
            sendable,
            deliveryFailure(error, refused ? "refused" : "uncertain"),
          );
        } catch (recordingError) {
          console.error(
            "Calendar invitation failure recording failed",
            id,
            recordingError,
          );
          failures++;
          failureStatus = 503;
          continue;
        }
        failures++;
        failureStatus = Math.max(failureStatus, 502);
        continue;
      }

      try {
        await dependencies.markSent(sendable);
        sent++;
      } catch (error) {
        console.error("Calendar invitation completion failed", id, error);
        failures++;
        failureStatus = 503;
      }
    }
    return json({ sent, failures }, failureStatus);
  };
}
