---
status: accepted
---

# Only a Shortfall gates Month release; the client reads it, never computes it

A day can read short in two ways. A **Shortfall** is a Coverage pool below the
Staffing minimum she set. An **Open shift** is a shift still uncovered, which
may leave the minimum met or have none behind it. The pool band shows both
together, as `max(Shortfall, Open shifts)` (ADR-0008). Only a Shortfall has to
be acknowledged before a Month release or confirm. A Shortfall is the one gap
that goes against an instruction she has already given; an Open shift left by
a Request off she approved does not. The release dialog therefore lists every
day that reads short once, under its stronger reason. Shortfall days carry the
acknowledgement. Open shift days are shown but ask nothing of her. So a red band
on a day the dialog does not make her acknowledge is deliberate, not a bug.
Grilled in #242.

The Shortfall is computed in one place: `section_staffing_for_month` in SQL. The
server's release check (`release_month_checked`,
`confirm_loaded_month_checked`) counts that figure, so the client reads the
same `shortfall` and `rn_shortfall` values rather than repeating the arithmetic
in Dart. The dialog's list and the server's check then cannot disagree. Until
now, `SectionStaffing.shortCount` recomputed it from raw counts in production.

## Considered options

- **One idea of "short": every red day must be acknowledged**, and the server's
  release check counts Open shifts too. Rejected: the acknowledgement would
  spend her attention on gaps she caused or approved, and teach her to click
  through it.
- **Show only the Shortfall days in the dialog**, as before. Rejected: "Review
  these days on the Schedule" listed fewer days than the Schedule showed red.
- **Compute the Shortfall in Dart** for instant readings while editing.
  Rejected: that is a second copy of the rule next to the one the server's
  release check uses, which is the drift this decision removes.

## Consequences

The in-memory test store still has its own copy of the minimum arithmetic
(`open_shifts.dart`). Whether that copy stays for test realism is #246's
question, not this one.
