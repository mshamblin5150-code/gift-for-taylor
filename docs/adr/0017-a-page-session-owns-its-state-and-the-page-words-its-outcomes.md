---
status: accepted
---

# A page's session owns its state; the page renders it and words its outcomes

`MonthGridPage` held the month's reads, three stream subscriptions, a 15-second poll, a midnight timer, and every Schedule command in its widget State: about 1,250 of its 2,770 lines. Every one of the 47 tests in `widget_test.dart` pumped the whole page to reach that logic, at forced view sizes, asserting on string keys and cell colours. No test covered a command failing. Grilled in #245, after #242 (Coverage reading) and #243 (Access) had removed the logic those decisions owned.

**A session module owns a page's data, liveness and commands; the page owns only view state, rendering and wording.** For the month page this is `MonthSession`, in `lib/schedule/month_session.dart`. It owns the required and adjunct reads, the `monthUpdates` subscription, the midnight reload, and the commands: edit, announce, start the month, drop with its Undo, and Month release. The page keeps the selected view, day and person, collapsed Sections, scroll positions, and printing, which ADR-0016 already moved behind its own module.

**The session is a `ChangeNotifier` exposing one immutable state.** `MonthSessionState` holds the grid, Coverage reading, Change announcement, Unreached changes this week, load error, busy flag and today, and is replaced whole on every change. The page listens with `ListenableBuilder`. The clock and timers are injected, so tests advance midnight and the poll without pumping. We chose this over a `ValueNotifier`, whose public setter would let the page write session state, over a `Stream` of states, which has no current value at the first frame, and over loose getters, which cannot be compared as one state and can disagree mid-update. It needs no package.

**A command returns a sealed outcome; the page chooses every sentence.** `edit()` returns `Saved | MonthNotStarted | Failed`, `drop()` returns `Swapped(undo) | Copied(undo) | NothingToSwap | Failed`, and so on. The page awaits the future its own gesture started, so no outcome can be lost, and an exhaustive `switch` means a new failure cannot go unworded. The drop's Undo is a token the page hands back to the session, which builds the inverse edit. Liveness never produces messages, only new state. We rejected Flutter's `Command` objects, whose listeners and `clearResult()` do what an `await` already does, and messages held in state, which solve a delivery problem that a gesture-started command does not have.

**A confirmation is a review, then a commit.** The session computes what the dialog must show, the page shows it, and the commit carries the review. For a Month release, `reviewMonthRelease()` lists the Shortfall days and the Open shift days (ADR-0014), and `releaseMonth(review)` acknowledges Shortfalls exactly when the review the Manager saw had them. Edit is a guard, then the cell sheet, then the commit; announce is the sheet, then the commit. We rejected a session that opens dialogs through a callback, which puts UI inside a command, and a pending confirmation held in state, which makes the dialog's lifetime part of the shared snapshot.

**Confirming a Loaded month and releasing a built month are one command.** The session picks the store call from the state it holds; the review says which kind it is, so the page can say "Confirm" or "Release". The Shortfall rule is the same for both, so it is tested once.

**A session lives as long as its data.** One `MonthSession` covers one month; navigating disposes it and creates the next, so a late read of the old month lands in a dead session instead of needing a guard. What belongs to the viewer rather than the month (the Swap and Open shift subscriptions, the poll, and the counts of work waiting on them) is a separate `PendingWork` that lives as long as the page.

**The session reports rejected writes.** Carrying out ADR-0015, every command's failure path calls `onAccessRejected` when the store raises `AccessRejected`. The Supabase adapters map Postgrest 42501, 401 and 403 to that type, so the session knows nothing of Supabase, and the in-memory store can inject it.

**Tests split by what they assert.** Assertions about store or session state are session tests against `InMemoryScheduleDatabase`. Rendering, gestures, dialog contents and the wording of each outcome stay widget tests, plus two or three end-to-end flows. Widget tests use the real session over the in-memory store, never a fake session, so there is one implementation to drift.

## Considered options

- **Commands only, as plain functions** like `readPendingApprovals`. Rejected: the subscriptions, timers and reload-after-command would stay in widget State, and so would the tests that have to pump to reach them.
- **One session that navigates between months.** Rejected: a month change becomes an internal transition, and a stale read from the old month has to be guarded instead of being impossible.
- **Month page only, not a house pattern.** Rejected: the shape, outcomes, review-then-commit and rejected-write decisions are not about months, and the next page with commands would reopen them.

## Consequences

This is the default for any page that grows commands. Other pages, such as Swaps, Requests off and Coverage settings, adopt it when they are next changed for another reason, not in a sweep.

The move fixes three things in passing: a drop's Undo is guarded by the same busy flag as the drop, a failed drop reads "Try again" instead of showing the raw error, and a failed month start now asks for Access again like every other command.

The view-size overrides, string keys and colour assertions in the widget tests come from the page's layout, not its logic, and are out of scope here.
