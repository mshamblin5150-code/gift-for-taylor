import { createClient } from "npm:@supabase/supabase-js@2.57.0";
import nodemailer from "npm:nodemailer@7.0.6";
import { invitationMessage, type Invitation } from "./calendar.ts";

Deno.serve(async (request) => {
  const secret = Deno.env.get("CALENDAR_WEBHOOK_SECRET");
  if (!secret || request.method !== "POST" ||
    request.headers.get("x-calendar-secret") !== secret) {
    return new Response("Unauthorized", { status: 401 });
  }
  const password = Deno.env.get("RESEND_SMTP_PASSWORD");
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!password || !url || !key) {
    return new Response("Calendar delivery is not configured", { status: 503 });
  }
  const client = createClient(url, key);
  const { data: pending, error } = await client
    .from("calendar_invitation_outbox")
    .select("*")
    .is("sent_at", null)
    .is("superseded_at", null)
    .order("last_modified")
    .limit(50);
  if (error) return new Response("Outbox lookup failed", { status: 503 });

  const transport = nodemailer.createTransport({
    host: "smtp.resend.com",
    port: 465,
    secure: true,
    auth: { user: "resend", pass: password },
  });
  let sent = 0;
  let failures = 0;
  for (const queued of pending ?? []) {
    const event = queued as Invitation;
    // Recheck each row because another edit may have superseded the snapshot.
    const { data: current } = await client.rpc("calendar_invitation_to_send", {
      p_id: event.id,
    });
    if (!current?.length) continue;
    try {
      await transport.sendMail(invitationMessage(event));
      const { error: markError } = await client.rpc("calendar_invitation_sent", {
        p_id: event.id,
      });
      if (markError) throw markError;
      sent++;
    } catch (sendError) {
      failures++;
      console.error("Calendar invitation delivery failed", event.id, sendError);
    }
  }
  transport.close();
  return Response.json({ sent, failures }, { status: failures ? 502 : 200 });
});
