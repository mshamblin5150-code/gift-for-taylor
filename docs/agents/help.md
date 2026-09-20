# Help maintenance

The offline Help catalog lives in `lib/help/help_page.dart`. When changing a
Schedule view or a page linked from the Schedule or Staff list, update its topic
in the same change. Give each capability its own topic with what it is, who can
do it, and concrete steps; add the phrases a Staff member would search for.
Check role visibility against `canEditSchedule` and `EditableSections`, and use
`CONTEXT.md` vocabulary. Run `test/help_page_test.dart` for search and role
behavior and the widget tests for both entry points.
