-- Only Invites issued after this migration use the 30-day default.
-- Existing rows retain their stored expires_at value.
alter table public.invites
alter column expires_at set default (now() + interval '30 days');
