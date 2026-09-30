---
status: accepted
---

# A Refusal is known by its code everywhere, and adapters reach SQL only through the guard

ADR-0018 said SQL raises a distinct code for each refusal the page words, and the Supabase adapter maps it to a typed exception. In practice the mapping took three shapes and was opt-in, one call at a time:

- **Enum families with app-side code extensions**, applied by eight `map*Refusal` wrappers.
- **One-off exceptions with a `refusalCode` getter**, whose literals were repeated in hand-written catches.
- **An inline `switch (error.code)` in the Ticket gateway**, with code-less enums and no Dart test.

Several adapters never opted in at all (#386). Pages imported adapter files to read a code. The month page pasted the same Ticket snack six times. Adding one refusal touched between four and ten files.

Because each call chose its own mapping, codes collided without anyone noticing:

- **P2831** meant both "a current Staff account is required" and "cannot work the offered shift".
- **P2845** meant three things.
- **P2812** and **P2795** each covered two different refusals, and one of them was worded wrongly.

A Ticket stores only the code, and it shows "Refusal: P2831" to the sender and the Maintainer alike. Grilled in #388.

## Decisions

**A Refusal is a rule verdict, and nothing else.** It is the app declining a request because a rule forbids it as things stand (see `CONTEXT.md`). An Access rejection is not a Refusal: the rule did not speak, and the answer is to ask for Access again, as ADR-0015 and ADR-0017 already do. A failure that goes away on retry is not a Refusal either. `AccessRejected` stays its own type, outside the contract.

**One code means one Refusal, everywhere, forever.**
- The unit is the meaning, not the raise site: six functions raising P2834 "Ticket not found" are one Refusal.
- A code identifies its Refusal on its own, without the operation that raised it. That is what lets a Ticket, the recent-actions log and the table test use it.
- A retired code is recorded and never reallocated, because Tickets keep old codes forever.
- Tickets already stored under the colliding codes keep their ambiguity; they are not backfilled.

**Each Refusal family is an enum whose values carry their code, behind one interface and one exception.** `abstract interface class Refusal { String get code; }` is implemented by one enum per operation family: `SwapProposalRefusal`, `MonthStartRefusal`, `ManagerHandoverRefusal`, the Ticket families, and so on. Each value declares its code in its constructor, so a Refusal cannot exist without one. The one-off exceptions become one- or two-value families. The only exception the guard throws for a known code is `Refused(Refusal refusal)`.

We rejected three alternatives:
- **A flat enum of every Refusal**, because every page's exhaustive switch would then span values it can never receive.
- **A per-family exception class**, which grows in pairs with the enums.
- **A `sealed` interface**, because Dart would then force every family into one library. Uniqueness is enforced by a test instead.

**The families live in `packages/schedule_rules`**, in one `refusals.dart` library, together with `Refused`, the list of every family (`knownRefusals`) and `retiredRefusalCodes`. The codes are a SQL contract (ADR-0018), not a Supabase detail. The package boundary keeps `supabase_flutter` out of every Refusal, and one file puts every code in view when a new one is chosen. The Staff and Ticket families move there from their gateways.

**Adapters never hold the Supabase client.** They receive a `Database` that exposes the client only inside `Future<T> run<T>(Future<T> Function(SupabaseClient) query)`. `run` translates what comes back:
- Postgrest 42501, 401 and 403 become `AccessRejected`.
- A code in `knownRefusals` becomes `Refused(refusal)`.
- Anything else is rethrown untouched.

Realtime channels and `auth` get their own narrow members, because they are not PostgREST calls that refuse. This makes #386's class of bug unrepresentable instead of audited.

We rejected two alternatives:
- **A `guard(() => …)` helper checked by grep**, because it is still opt-in.
- **Translation inside the HTTP client**, because it depends on Postgrest's error-wrapping internals and loses the call's stack.

**Session outcomes carry the typed family.** Examples are `SwapProposeRefused(SwapProposalRefusal)` and `StartMonthRefused(MonthStartRefusal)`. A session narrows `Refused` with `when e.refusal is TheFamily`. A `Refused` from a family the session does not expect is a contract bug: it becomes the session's plain `Failed`, with a debug assert. No outcome carries a raw `Object? error`, which restores ADR-0017's sealed outcomes. A generic `Refused(Refusal)` outcome was rejected because the page's wording switch could not be exhaustive over it.

**A page shows a Refusal through one presenter and a scope.**
- **The scope.** Each page puts `TicketScope(screen: TicketScreen.…, month: …)` around its body. `TicketScreen` is an enum holding the label a Ticket stores. The scope records the screen visit when it mounts.
- **The presenter.** `showRefusal(context, refusal, sentence)` reads the nearest scope and shows the sentence with "Put in a ticket about this", carrying the code, the screen and the month. `RefusalTicketButton(refusal)` does the same for inline forms.
- **The page's part.** The page keeps only its exhaustive wording switch.

The nearest ancestor is correct by construction, including for dialogs and back navigation. Mutable "current screen" state on the launcher was rejected because it names whichever screen last announced itself.

**Ticket Refusals are full Refusals, but Ticket pages do not offer a Ticket.** Offering "put in a ticket about this" on the put-in form would loop. On a Ticket's own page, the sender already has the thread. `TicketScreen` has no Ticket-page values, so the presenter cannot be used there.

**Pages only the Maintainer reaches do not offer a Ticket either** (added 2026-09-30, grilled in #387). A Ticket tells the designer something; on the break-glass page the sender would be the designer, who is also its only reader. Its Refusals are full Refusals with codes, shown as a plain sentence. The page has no `TicketScope` and `TicketScreen` has no value for it, which is the same mechanism as the Ticket pages.

**Bare `raise exception` is ratcheted out, not swept.**
- **Authority checks.** A check about who may act raises 42501, so the guard makes it `AccessRejected` and it needs no wording.
- **Rule checks.** A rule check gets its own Refusal code.
- **No new bare raises.** CI fails any new migration that raises without an `errcode`.
- **The existing ~80.** Functions that still raise P0001 are converted when they are next touched, as ADR-0017 is adopted page by page. The Repair functions (#387) are the first.

Many of the ~80 are input-shape checks the client already prevents, so they are genuine failures if they ever fire.

**One table test holds the contract.** A package test over `knownRefusals` checks three things:
- **Unique.** No two values share a code.
- **Raised.** Every known code is raised with `errcode` somewhere in `supabase/migrations`.
- **Accounted for.** Every `P` code raised in any migration is known, retired, or on a short internal list (P9001, which is caught inside `preview_*`).

The third direction is what catches the next unmapped or colliding code before a page words it "Try again". Beside it:
- A fake-`Database` test per family, covering both translations.
- One widget test that a refusal snack offers a Ticket carrying the scope's screen, the month and the code.

## Considered options

- **Keep per-call mapping, and fix #386 by wrapping the missing calls.** Rejected as the end state: it is how the collisions and the unmapped adapters happened. #386 is subsumed by the guard instead.
- **Codes unique per operation, with a Ticket storing the operation beside the code.** Rejected: every consumer of a stored code would have to carry a pair, and the Maintainer would still read an ambiguous number.
- **Treat P0001 as a generic Refusal that shows SQL's message.** Rejected: pages would show backend text, contrary to ADR-0018, and a Ticket would store a code that names nothing.
- **Give every bare raise a code in this change.** Rejected for size: each one needs its own wording decided, and the seam works the same whatever the number of codes.

## Consequences

The colliding codes are renumbered in SQL first, because the uniqueness test cannot pass until then:
- The Swap eligibility triggers move from P2831 to P2846.
- "Ticket thread message not found" moves from P2845 to P2847.
- The Repair's "Ticket not found" joins P2834.
- "No Call-in to withdraw" moves from P2812 to P2848, with its own sentence.
- "Section has Schedule history" moves from P2795 to P2849, with its own sentence.

P2831 and P2845 keep their Ticket meanings, because the client already maps them that way.

The Manager's approval queue offers a Ticket on a refused Swap approval, which it did not before.

`lib/refusal_code.dart`, the eight `map*Refusal` wrappers, `mapAccessRejected`, the Ticket gateway's own access check, every `refusalCode` getter and the pasted snack blocks are deleted. `access_rejected_write_test.dart` and `staff_refusal_mapping_test.dart` are replaced by the table test and the per-family adapter tests.

This carries out ADR-0017 and ADR-0018 and contradicts neither. #387 is decided in passing: the Maintainer-only check raises 42501.
