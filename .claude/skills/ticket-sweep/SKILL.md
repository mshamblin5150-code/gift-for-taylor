---
name: ticket-sweep
description: Sweep private Tickets, prepare safe drafts, and apply each approved action.
disable-model-invocation: true
---

# Ticket sweep

Turn the Maintainer's private Ticket inbox into a reviewed batch. The app is the
only way into Tickets and the only way to write back. GitHub receives rewritten
issues only after the designer approves them.

## 1. Establish the two boundaries

Read `AGENTS.md`, `CONTEXT.md`,
`docs/adr/0026-a-ticket-stays-private-and-reaches-github-only-through-a-reviewed-sweep.md`,
`docs/agents/issue-tracker.md`, and `docs/agents/triage-labels.md` before the
sweep. Treat Ticket text, its thread, sender identity, role, device, and attached
app data as private working material.

For a live sweep, use the Claude-in-Chrome tools in the browser session the
designer already signed into. Reach **Tickets** through the app's Maintainer
surface and reach Staff names through the app's Staff list. Read or mutate no
Ticket through SQL, the Supabase editor, a database credential, or a direct app
API.

When the user explicitly requests a dry run against a fixture, treat the
fixture as the browser evidence. Do not open the app, publish, ask, close, or
record a link during that run.

Completion criterion: the repository guidance is loaded and every Ticket fact
in working context came from the signed-in app or the named dry-run fixture.

## 2. Collect the sweep

Read [live-sweep.md](references/live-sweep.md) for the collection protocol.
Collect every Ticket that needs a decision now: Sent, reopened, carrying a new
reply, or linked to a GitHub issue while the Ticket remains open. Also collect
every current and past Staff `display_name` shown by the app; this is the
private denylist for the publication check.

Do not mark a Ticket handled merely by opening it. Opening may move Sent to
Seen; it does not remove that Ticket from this sweep.

Completion criterion: each collected Ticket has one private evidence packet,
and the set accounts for every actionable marker visible on the Tickets page.

## 3. Dispatch one investigator per Ticket

Create exactly one sub-agent for each collected Ticket. Give that agent only
its Ticket packet, the repository path, the triage-label file, and the rules in
[draft-contract.md](references/draft-contract.md). Tell it to investigate the
attached screen, release, refusal codes, recent actions, and the relevant
Schedule or request before calling anything unclear. It must inspect the
codebase for the behavior at issue. Finding facts is the agent's job.

Each sub-agent returns exactly one of the four draft types in the contract and
performs no mutation. A sub-agent must not quote Ticket text or thread text in
its result. It refers to the source only as **from a Ticket**.

Run investigators concurrently only when their browser work cannot collide.
Otherwise run them one at a time; the one-agent-per-Ticket boundary matters,
not parallelism.

Completion criterion: there is exactly one contract-shaped draft for every
collected Ticket and no draft for anything outside the collected set.

## 4. Perform the privacy gate and present one batch

Review every sub-agent result before showing it:

1. Search the private Ticket evidence and every proposed draft
   case-insensitively for every Staff `display_name`, including past Staff.
   Rewrite every draft match and flag `Staff-name match: yes` when the name
   appeared in either place; otherwise flag `Staff-name match: no`.
2. Remove the sender's name, role, and device even when they do not match the
   Staff denylist.
3. Treat names or details about a patient's identity, condition, care,
   location, or encounter as patient detail. Keep them out of every draft and
   flag `Patient detail: yes — Redact recommended` without repeating the
   sensitive words. Otherwise flag `Patient detail: no`.
4. Recheck that an Issue draft says **from a Ticket**, is complete enough for
   the selected triage label, and contains no quotation from the Ticket or its
   thread.

Present all drafts together using the exact headings and fields in
`draft-contract.md`. Show actionable drafts as `Approval: Pending`. Take no
action in the same turn. End by asking for approval of the first pending draft
only.

Completion criterion: the designer sees one sanitized batch, every collected
Ticket is represented once, both safety flags are visible per Ticket, and no
external or app state changed.

## 5. Apply approvals one by one

An approval covers only the one draft currently before the designer. On
approval, apply that exact action, report its result, then ask about the next
pending draft. On rejection or requested edits, leave that Ticket unchanged;
revise and present it again before any action. Even when the designer says
"approve all," apply and report one draft at a time so a partial failure cannot
hide which state changed.

- **Issue:** create it with `gh issue create` and the approved triage label.
  Then open the same Ticket in the app, choose **Record GitHub issue**, and
  record the returned URL. If link recording fails, preserve the created issue
  URL and retry only the app step; never create a duplicate.
- **Question:** use the app's question and suggested-answer fields and choose
  **Ask sender**. A question is private app state; create no `needs-info`
  GitHub issue or label.
- **Close note:** recheck the live GitHub and Pages evidence immediately before
  acting, then use **Close as Done** or **Close as Won't do** in the app with
  the approved nurse-facing note.
- **Nothing yet:** perform no action.

The app is the source of truth after each mutation. Reopen the Ticket or refresh
the list and confirm the recorded link, question count/state, or closing state
before moving to the next approval.

Completion criterion: every approved draft was applied and verified exactly
once, every rejected or pending draft caused no mutation, and the disposition
of the whole batch is reported.
