# Help maintenance

The offline Help catalog lives in `lib/help/help_page.dart`. Follow
[ADR-0011](../adr/0011-help-follows-reader-roles-and-tasks.md) when writing or
changing a topic. For every user-facing behavior change, update the affected
Help guidance and search terms in the same change. Audit for a missing topic
when adding a capability; split a topic when it combines tasks that readers
need to distinguish. Use `CONTEXT.md` vocabulary, and include the everyday
phrases a reader would search for.

Write the immediate answer first, followed by ordered steps and the expected
result. Add a reason or troubleshooting only where it helps. State who can do
the action. Manager, Night scheduler and Administrator Help includes Staff
guidance; clearly mark actions reserved for the Manager. Staff Help shows
Staff-relevant guidance. Check the labels against actual permissions,
including `canEditSchedule` and `EditableSections`.

Have an independent agent try to answer a realistic reader question using only
each changed topic. Check that it can find the topic and follow the steps
without guessing; flag unexplained app terms, multi-action steps and missing
outcomes. Run `test/help_page_test.dart` for search and role behavior and the
widget tests for Help entry points. Help must remain bundled for offline use
and searchable.

ADR-0011 records the target contract. The #167 rewrite and Administrator Help
routing are still pending; do not assume the current catalog already meets it.
