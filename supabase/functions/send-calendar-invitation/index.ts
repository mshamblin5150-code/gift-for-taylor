import { createClient } from "npm:@supabase/supabase-js@2.57.0";
import nodemailer from "npm:nodemailer@7.0.6";
import { invitationMessage } from "./calendar.ts";
import {
  type ClaimedInvitation,
  type ClaimedInvitationMessage,
  createCalendarInvitationHandler,
  isCalendarInvitationRequestAuthorized,
} from "./delivery.ts";

function deliveryClaim(invitations: ClaimedInvitationMessage) {
  const invitation = invitations[0];
  return {
    p_id: invitation.batch_id ?? invitation.id,
    p_recipient: invitation.recipient,
    p_method: invitation.method,
    p_claim: invitation.delivery_claim,
  };
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("CALENDAR_WEBHOOK_SECRET");
  if (!isCalendarInvitationRequestAuthorized(request, secret)) {
    return new Response("Unauthorized", { status: 401 });
  }
  const password = Deno.env.get("RESEND_SMTP_PASSWORD");
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!password || !url || !key) {
    return new Response("Calendar delivery is not configured", { status: 503 });
  }
  const client = createClient(url, key);
  const transport = nodemailer.createTransport({
    host: "smtp.resend.com",
    port: 465,
    secure: true,
    auth: { user: "resend", pass: password },
    connectionTimeout: 30000,
    greetingTimeout: 30000,
    socketTimeout: 120000,
  });
  const handler = createCalendarInvitationHandler({
    secret,
    claim: async (id) => {
      const { data, error } = await client.rpc("calendar_invitation_claim", {
        p_id: id,
      });
      if (error) throw error;
      return (data as ClaimedInvitation[] | null) ?? [];
    },
    beginSend: async (invitations) => {
      const { data, error } = await client.rpc("calendar_invitation_sending", {
        ...deliveryClaim(invitations),
      });
      if (error) throw error;
      const currentIds = new Set((data as string[] | null) ?? []);
      return invitations.filter((invitation) => currentIds.has(invitation.id));
    },
    send: async (invitations) => {
      await transport.sendMail(invitationMessage(invitations));
    },
    markSent: async (invitations) => {
      const { data, error } = await client.rpc("calendar_invitation_sent", {
        ...deliveryClaim(invitations),
      });
      if (error || data !== true) throw error ?? new Error("Claim was lost");
    },
    markFailed: async (invitations, failure) => {
      const { data, error } = await client.rpc(
        "record_calendar_invitation_failure",
        {
          ...deliveryClaim(invitations),
          p_outcome: failure.outcome,
          p_error_code: failure.code,
          p_status_code: failure.statusCode,
          p_error_message: failure.message,
        },
      );
      if (error || data !== true) throw error ?? new Error("Claim was lost");
    },
    release: async (invitations) => {
      const { error } = await client.rpc("calendar_invitation_failed", {
        ...deliveryClaim(invitations),
      });
      if (error) throw error;
    },
  });
  try {
    return await handler(request);
  } finally {
    transport.close();
  }
});
