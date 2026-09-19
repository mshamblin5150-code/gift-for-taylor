# Version-one data model

This design covers version one of the ER Schedule. The walking skeleton creates
only `sections`, `staff_members`, `staff_accounts`, `schedule_months`, and
`schedule_cells`; later tickets add the tables they use. Staff names and contact
details belong only in Supabase and must never be committed.

## Identity and access

- `staff_members`: the durable Staff list record. It stores display name, cell
  number, active state, Last day, and the current broad role. Deactivation never
  deletes history.
- `staff_accounts`: the accepted link from one Supabase Auth identity to one
  Staff member. No row means the email account has no access.
- `invites`: a hashed, single-use token tied to a Staff member, with creation,
  expiry, acceptance, and revocation timestamps. Accepting an Invite creates the
  `staff_accounts` link; resending revokes the prior token.
- `role_assignments`: dated Manager, administrator, Night scheduler, and Staff
  member roles. The current role on `staff_members` is a read optimization.
- `night_scheduler_sections`: dated permission for a Night scheduler to edit a
  Section.

All shared tables use row-level security. Anonymous callers and authenticated
accounts without an accepted Invite see no rows. Active Staff members can read
released Schedules. The Manager and administrator can manage the Staff list;
the Manager and assigned Night scheduler can edit only the cells their roles
allow. Deactivation immediately removes every policy path.

## Schedule structure

- `sections`: ordered Section labels.
- `staff_section_assignments`: a Staff member's Section and row order with
  effective-from and effective-through dates. Dated rows preserve moves.
- `schedule_months`: the first day of the month and its `unpublished` or
  `released` state, including who performed the Month release and when.
- `schedule_cells`: one Staff member, date, Section snapshot, and free-text Shift
  code. A database constraint keeps one cell per person per date in a month.
- `shift_legend_entries`: shortcuts and optional start/end times. The legend is
  not a foreign key because off-legend Shift codes are valid.
- `schedule_changes`: append-only old/new cell values, actor, timestamp, and an
  `announced_at` marker. This is both the change log and the source for the
  unannounced tray and Change announcements.

Section and Staff member identifiers are snapshotted onto historical records
where needed so later renames, moves, or deactivation do not rewrite history.

## Requests and coverage

- `requests_off` and `request_off_dates`: requester, dates, optional reason,
  email-copy confirmation, decision, decision reason, actor, and time.
- `swaps` and `swap_legs`: proposer, requested colleague, the two shifts,
  colleague response, and final Manager decision.
- `open_shifts`: the uncovered date, Shift code, Section/role pool, source, and
  open/filled/cancelled state.
- `open_shift_pickups`: applicant and Manager decision. Nursing eligibility
  groups RN and LPN; CNA and unit-clerk pools remain separate.
- `approval_items`: a queryable projection over pending Requests off, Swaps, and
  pickups rather than a second source of truth.

Approvals and the Schedule cell changes they cause happen in one transaction and
also append `schedule_changes` rows.

## Delivery channels

- `calendar_feed_tokens`: one hashed active token per Staff member, rotation and
  revocation timestamps. A feed includes working shifts only; off-legend codes
  become all-day events. Deactivation blocks the feed immediately.
- `push_subscriptions`: endpoint and encrypted browser subscription material per
  Staff member/device, plus last-used and revoked timestamps.
- `in_app_notices`: recipient, kind, payload reference, read time, and creation
  time for Month releases and later request activity.

Change announcements are generated from `schedule_changes` and sent from the
scheduler's own phone. No SMS body, delivery receipt, or hospital data is stored.

## Deletion and audit rules

Operational rows are deactivated, revoked, or cancelled rather than deleted.
The append-only change log keeps the actor's Staff member identifier and a safe
display-name snapshot. Calendar tokens and sign-in access stop on deactivation,
while past Schedules remain readable to authorized people.
