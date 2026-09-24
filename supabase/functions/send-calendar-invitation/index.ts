import { createClient } from "npm:@supabase/supabase-js@2.57.0";
import nodemailer from "npm:nodemailer@7.0.6";
import { invitationMessage } from "./calendar.ts";
import {
  type ClaimedInvitation,
  createCalendarInvitationHandler,
} from "./delivery.ts";

Deno.serve(async (request) => {
  const secret = Deno.env.get("CALENDAR_WEBHOOK_SECRET");
  if (
    !secret || request.method !== "POST" ||
    request.headers.get("x-calendar-secret") !== secret
  ) {
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
  });
  const handler = createCalendarInvitationHandler({
    secret,
    claim: async (id) => {
      const { data, error } = await client.rpc("calendar_invitation_claim", {
        p_id: id,
      });
      if (error) throw error;
      return (data?.[0] as ClaimedInvitation | undefined) ?? null;
    },
    send: async (event) => {
      await transport.sendMail(invitationMessage(event));
    },
    markSent: async (id, claim) => {
      const { error } = await client.rpc("calendar_invitation_sent", {
        p_id: id,
        p_claim: claim,
      });
      if (error) throw error;
    },
    release: async (id, claim) => {
      const { error } = await client.rpc("calendar_invitation_failed", {
        p_id: id,
        p_claim: claim,
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
