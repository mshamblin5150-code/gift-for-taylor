# Live sweep collection

Use this branch only for a live sweep. Keep all collected material private.

## Tickets

1. Select the existing signed-in app tab with Claude in Chrome. If there is no
   signed-in tab, stop and ask the designer to sign in; do not handle
   credentials.
2. Open the app menu and choose **Tickets** under the Maintainer surface. The
   Maintainer reads Tickets without opening a Repair.
3. Inventory the whole list before opening details. Include every card marked
   Sent, Reopened, or New reply, and every non-closed Ticket with a recorded
   GitHub issue. Scroll until the list is exhausted.
4. Open each included Ticket and record its kind, state, text, private thread,
   question count, GitHub issue link, and attached context: screen, Month,
   release, refusal codes, recent actions, and device. Device is investigation
   context only and cannot enter a draft.
5. Follow the attached screen and identifiers through the app to inspect the
   relevant Schedule or request. Use the app's visible state. If access is
   unavailable, record that absence rather than replacing it with a database
   query.

Opening a Sent Ticket marks it Seen. Keep it in the current working set.

## Staff denylist

Open the app's Staff list with the Maintainer's normal read access. Collect the
exact `display_name` of every current and past Staff member. The list is a
private publication denylist, not content for an issue or the final report.

## Evidence packet

Give one packet to one investigator. It contains:

- a local Ticket key used only to pair the response;
- all Ticket and thread facts from the app;
- relevant Schedule or request facts gathered through the app;
- the attached release and recent-action facts;
- the linked GitHub issue, if any;
- the Staff denylist; and
- the instruction to inspect repository code and return exactly one draft.

Do not persist packets to the repository or shell history.
