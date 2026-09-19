import { createClient } from "npm:@supabase/supabase-js@2.57.0";
import webpush from "npm:web-push@3.6.7";

type Notice = {
  id: string;
  staff_member_id: string;
  title: string;
  body: string;
  month_start: string | null;
};

Deno.serve(async (request) => {
  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (
    !secret || request.method !== "POST" ||
    request.headers.get("x-push-secret") !== secret
  ) {
    return new Response("Unauthorized", { status: 401 });
  }

  const event = await request.json();
  if (
    event.type !== "INSERT" || event.schema !== "public" ||
    event.table !== "staff_notices"
  ) {
    return new Response("Invalid event", { status: 400 });
  }

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  // Re-read the notice rather than trusting fields supplied in the webhook.
  const { data: notice, error: noticeError } = await client
    .from("staff_notices")
    .select("id, staff_member_id, title, body, month_start")
    .eq("id", event.record?.id)
    .single<Notice>();
  if (noticeError || !notice) {
    return new Response("Notice not found", { status: 404 });
  }

  const { data: subscriptions, error } = await client
    .from("push_subscriptions")
    .select("endpoint, subscription")
    .eq("staff_member_id", notice.staff_member_id);
  if (error) return new Response("Subscription lookup failed", { status: 500 });

  webpush.setVapidDetails(
    Deno.env.get("VAPID_SUBJECT")!,
    Deno.env.get("VAPID_PUBLIC_KEY")!,
    Deno.env.get("VAPID_PRIVATE_KEY")!,
  );
  let failures = 0;
  await Promise.all(
    (subscriptions ?? []).map(async ({ endpoint, subscription }) => {
      try {
        await webpush.sendNotification(
          subscription,
          JSON.stringify({
            title: notice.title,
            body: notice.body,
            url: notice.month_start ? `?month=${notice.month_start}` : "./",
          }),
          { TTL: 86400 },
        );
      } catch (sendError) {
        const status = (sendError as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) {
          await client.from("push_subscriptions").delete().eq(
            "endpoint",
            endpoint,
          );
        } else {
          failures++;
          console.error("Push delivery failed", status ?? sendError);
        }
      }
    }),
  );
  return Response.json({
    sent: (subscriptions ?? []).length - failures,
    failures,
  }, {
    status: failures ? 502 : 200,
  });
});
