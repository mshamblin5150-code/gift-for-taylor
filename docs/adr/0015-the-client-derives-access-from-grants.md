---
status: accepted
---

# The client derives Access from grants

The client knew authority only as one role string from `current_access_role()`, which each page combined with booleans it fetched itself. Pages compared `'manager'`, `'administrator'` and `'maintainer'` dozens of times, wrote "can edit this cell" three ways, and ranked roles so that a person holding two Access grants lost one of them. The in-memory store had drifted further: it treated Manager and Night scheduler as mutually exclusive and had no Administrator or Maintainer. This decision from #243 carries out ADR-0013 on the client. It does not reopen ADR-0013's rules.

The client reads the viewer's grants once, through a single `current_access()` read: Manager, Administrator, Maintainer, Night scheduler Sections, and the viewer's own Staff member, if any. An **Access** value in `schedule_rules` derives every authority question from those grants, such as whether the viewer can edit a Section, run the Schedule, manage Staff, manage the Unit, or read an unreleased month. **Pages decide only by asking Access.** A page may display grants, for example on Staff details or to choose Help's reader roles, but it never combines grants to decide what to offer. The database remains the enforcer. Access decides only what the client offers, so a stale or wrong answer produces a rejected write, not a breach.

We chose to derive answers on the client over having the server return them. With server answers, every new question would need a migration, and Staff details would still need the grants to show them. The cost is that the rules now exist in two places, Dart and SQL. To contain that, the questions that exist on both sides are tested from one scenario file. The Dart tests read it directly, it generates the pgTAP test, and a check fails if the generated file is stale. The in-memory store also answers from Access, so the fake cannot drift from the client.

The Maintainer is a grant of its own. The database treats the Maintainer as `'manager'`, but Access never does, because ADR-0013 separates capability from responsibility. Manager-level questions accept either grant. Questions about the viewer's own Schedule, such as Notices, My calendar, Swaps and Requests off, need a Staff member, which the Maintainer does not have.

This extends ADR-0013 on one point. **Night schedulers read the Change log.** They can then see when the Manager overrode their edits. The server already allowed it, and the client now offers it.

Grants change rarely, so Access is not live. It is re-read when the app returns to the foreground, after a Manager handover, and when the server rejects a write as unauthorized. We chose that over a realtime subscription to grant rows.
