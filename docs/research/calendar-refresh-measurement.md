# Calendar feed refresh measurement

Issue #104. The earlier research in this directory is a set of hypotheses, not measurements from our Calendar feed. Record results here only after the trials below run. Use `[Measured]` for our own observations and retain `[Unconfirmed]` when a trial has too little data.

## Instrumentation

Migration `20260920230000_calendar_feed_measurements.sql` records successful-token GETs for explicitly enrolled Calendar subscriptions in `calendar_feed_fetches`: Calendar subscription ID, UTC request time, user-agent, presence of `If-None-Match` and `If-Modified-Since`, and the forwarded source address. Enrollment expires automatically. It never records the bearer token, validator values, or Schedule contents. Other, invalid, and revoked links produce no row. Only the service role can read the table; do not copy addresses or token URLs into GitHub issues or this file. The existing `last_fetched_at` remains the UI's latest-check time.

The feed writes the history row before generating the response. A row proves a request arrived, not that the caller received a `200` or `304`. The forwarding header may contain a proxy address or a client-supplied value; corroborate any server-versus-device conclusion with Mac power state, user-agent, and independently known device network addresses. If the header is absent, do not infer where the request originated. The current feed emits `REFRESH-INTERVAL:PT5M` and `X-PUBLISHED-TTL:PT15M`; this setup alone cannot separate the effects of those properties.

## Trial setup

1. Deploy the migration and the updated `calendar-feed` function together. In a nonclinical throwaway Staff account, switch to Calendar feed and create a distinct Calendar subscription for each trial arm. Enroll only those subscription UUIDs with `update public.calendar_feed_tokens set measure_fetches_until = now() + interval '8 days' where id in (...)` in the SQL editor. Keep the generated URLs private. Record only the subscription UUIDs, UTC start/end times, calendar app and version, account location, power/network conditions, refresh setting, and any deliberate manual refresh in a private trial log.
2. Subscribe a device-local iPhone Calendar, an iCloud-located Calendar, Google Calendar *From URL*, classic Outlook for Windows, and Outlook on the web or Outlook.com. Give each product its own Calendar subscription except for the Google sharing trial: use two throwaway Google accounts with the **same** test URL and a third with a **different** URL. Record which Outlook product and account type was used; they have different pollers. Keep the feed content unchanged during the baseline. A 7-day baseline captures long gaps and day-of-week effects.
3. On a Mac, put the iCloud subscription in iCloud and set auto-refresh to 5 minutes. After confirming requests, shut the Mac down for at least 24 hours while leaving the iPhone online. Compare requests during the off interval with those before it. Separately observe a device-local iPhone subscription under the available Fetch New Data settings. Mark manual refreshes so they are excluded from automatic cadence.
4. Inspect conditional-request rates for each Calendar subscription. The existing response test verifies that a matching validator returns `304`; request history establishes which clients actually send validators. To test whether clients honor the two ICS refresh hints, use otherwise identical feeds with different hint values in a separately controlled experiment. The current fixed hints cannot answer that question.
5. At the end, export aggregate counts and intervals only. Confirm each trial had uninterrupted observation before calling an absence of requests meaningful. Delete source addresses and request history after analysis, within 14 days of the last trial. Keep only aggregate results here.

## Analysis SQL

Run in the Supabase SQL editor with the trial UUIDs and UTC window substituted. Never export the `forwarded_for` column to the repo.

```sql
-- Each automatic inter-request interval, in minutes. Review and exclude
-- manually triggered fetches using the private trial log.
select subscription_id, fetched_at, user_agent,
  extract(epoch from fetched_at - lag(fetched_at) over (
    partition by subscription_id order by fetched_at, id
  )) / 60 as minutes_since_previous,
  if_none_match, if_modified_since
from public.calendar_feed_fetches
where subscription_id in ('<trial-uuid-1>', '<trial-uuid-2>')
  and fetched_at >= '<start-utc>' and fetched_at < '<end-utc>'
order by subscription_id, fetched_at, id;

-- Count requests and conditional requests by trial arm.
select subscription_id, count(*) as requests,
  count(*) filter (where if_none_match) as etag_requests,
  count(*) filter (where if_modified_since) as date_requests,
  min(fetched_at) as first_fetch, max(fetched_at) as last_fetch
from public.calendar_feed_fetches
where subscription_id in ('<trial-uuid-1>', '<trial-uuid-2>')
  and fetched_at >= '<start-utc>' and fetched_at < '<end-utc>'
group by subscription_id;

-- After writing aggregate findings, purge the completed experiment.
delete from public.calendar_feed_fetches
where subscription_id in ('<trial-uuid-1>', '<trial-uuid-2>')
  and fetched_at < '<end-utc>';
```

Report for each arm: trial dates, number of automatic fetches, median and range of intervals, conditional-request fraction, and the longest observed gap. For the two-account Google test, count requests at the shared URL and compare with the distinct URL; one shared stream suggests but does not by itself prove per-URL polling. For the Mac-off test, distinguish continuing origin requests from actual iPhone appearance time. A feed fetch does not prove the changed shift reached the Calendar display.

## Results

Pending deployment, throwaway subscriptions, and the 7-day observation window. No platform-specific refresh interval has been measured yet.
