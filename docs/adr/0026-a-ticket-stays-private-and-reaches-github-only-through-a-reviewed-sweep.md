---
status: accepted
---

# A Ticket stays private and reaches GitHub only through a reviewed sweep

A Staff member who hit a problem in the app had no way to tell anyone except
the designer in person. The request was for reports to land straight in this
repository's issues, leaving only triage to do. Grilled in #346.

## The repository is public, so a Ticket lands in the app first

This repository is public. Filing a nurse's words as an issue would publish
them to the open internet at once, and deleting the issue afterwards would not
take them back: GH Archive records every public event, issue text included,
within minutes, and watchers receive it by email. Two things will turn up in
that text: colleagues' names and shifts ("Dana's swap for the 14th didn't go
through"), and patient detail typed at 03:00 by someone who has been with
patients all night. The first line of `CONTEXT.md` says the tool is built
never on patients, and an unreviewed free-text box would be the one place that
rule could fail.

**A Ticket is stored privately in the app and read only by the Maintainer.**
Posting straight to GitHub with a disclaimer was considered and rejected. A
disclaimer gets the consent of the person reading it, not of the colleague she
names, and patient detail is not hers to consent to publishing. Warnings stop
being read by the third use. Making the repository private was not chosen
either: it would have been a decision about the whole project, made as a side
effect of this one. Every product surveyed (Instabug, Sentry User Feedback,
Canny, Intercom, Linear) lands user-written feedback in a private inbox.
Open-source apps that use public trackers ask the user to file the issue
themselves.

## Why "Ticket"

The obvious word, *report*, already means the shift handover of patients.
A nurse gives or gets report at every shift change, so a "Send a report"
button would bring patients into the one box meant to keep them out.
*Ticket* is what hospital staff already say for telling IT something is wrong,
and it is the designer's word too. Its kind (*Something's wrong*, *An idea*,
*A question*) carries the difference, so ideas fit, as they do in ServiceNow
and Jira Service Management.

## Reading Tickets is hat work, not a Repair

**The Maintainer reads Tickets wearing the hat, without breaking the glass.**
ADR-0020's control only works because the Manager actually reads every Repair
Notice. If every Ticket opened a Repair, she would be told about button
colours and learn to skim those Notices. Reading and publishing a Ticket touch
no Unit data and use no Manager authority. **A Ticket is what may cause a
Repair, not the first half of one:** when a fix needs Manager authority, the
Repair names the Ticket as its cause. The Manager sees that a Ticket prompted
it, but never who sent it. If Tickets led back to the manager, the awkward
ones would stop coming.

## The app never talks to GitHub

**Publishing happens in a Claude Code session, not in the app.** The
`ticket-sweep` skill runs on demand on the designer's machine. It reads
Tickets through the app's own Maintainer surface in Chrome, signed in as the
designer wearing the hat, triages them, and sends sub-agents to each one. Its
output is always a draft that the designer approves one by one: an issue
written in the drone's own words, a question to the sender, or a close note.

The in-app alternative, an Edge Function calling GitHub with a token held in
Vault, was rejected. It would put a credential that can write to a public
repository in the app, and a publish screen in front of it, to automate a step
whose whole purpose is that a person does it. The sweep uses the `gh` login
the designer already has. Reading through the Supabase SQL editor was rejected
too: it runs as the database owner and would skip the rules ADR-0018 keeps in
SQL, so Seen would be recorded against nobody and the sender's close Notice
would depend on a trigger happening to cover it. A scheduled cloud routine
would need a machine credential with the Maintainer's reach over private text,
which is the second identity ADR-0020 declined. Since every draft needs the
designer's approval anyway, the trigger is a push when something arrives, not
a timer.

**What reaches GitHub is written by the drone and never quotes the Ticket.**
The sender's words, the thread and her identity stay in the app. The draft
carries the kind, screen, Month, release and refusal codes, and is checked
against Staff-list names before the designer sees it. A person rewriting a
report can judge whether a quote is harmless. A drone needs a rule it cannot
reason its way around. Drafts go out only with the designer's approval. That
can be relaxed later if it proves unnecessary. A published patient detail
cannot be taken back.

## The sender hears back

A Ticket moves from *Sent* to *Seen*, *Waiting on you*, then *Done* or
*Won't do*. Seen is set when the Maintainer opens it, so "someone read this"
costs nothing. The sender receives a Notice with the reason when it closes,
because the best predictor of a second suggestion is hearing back about the
first. **Done means live in a release** (ADR-0022), not merged: telling a
nurse it is fixed while her app still does the old thing is worse than silence.
She may reopen a closed Ticket for 14 days. After that a new Ticket, with
fresh context, is the better record.

**`needs-info` lives only in the app.** The triage label means "waiting on
reporter", and the reporter never sees GitHub, so a Ticket needing more is
answered through a private thread before anything is published. The drone may
ask at most two questions, one at a time, each with a guess she can confirm
with a tap. It follows the grilling skill's rule that finding facts is the
agent's job, but it does not run a full grilling session: a nurse between
patients stops at the second question. Past two, the designer asks in person.

## Consequences

- Only signed-in people can put in a Ticket, from the menu on any screen or
  from any refusal message, with the refusal code attached. A signed-out form
  would be an anonymous write path open to spam. Recording sign-in refusals
  automatically is tracked separately.
- The app attaches who, where, when, the release, the device, and recent
  actions and refusal codes, and shows the sender all of it. There is no
  screenshot: it mostly shows what the Maintainer can open anyway, and it
  adds the most material that must not be published.
- Putting in a Ticket is bounded per person in SQL, duplicates are merged, and
  pushes to the Maintainer are combined.
- A Ticket's text and thread are erased 90 days after it closes. The
  Maintainer can redact text at once, and the sweep flags anything that looks
  like patient detail. The rest of the record stays, so a Repair's link to its
  cause survives.
- Tickets go to whoever wears the Maintainer hat. Administrators and the
  Manager do not see them.
- Built as #364 (put in and read), #365 (close and reopen), #366 (thread),
  #367 (push and bounds), #368 (refusal offer and recent actions), #369
  (erasure and Redact), #370 (Repair cause) and #371 (the `ticket-sweep`
  skill).
