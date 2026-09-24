const phoneInstallGuidance = '''Why this matters: on an iPhone or iPad, ER Schedule can only send you shift notifications from a Home Screen icon. In Safari on its own, it cannot.

iPhone:
1. Open Add ER Schedule. You can find it on the screen after your Invite or in Settings.
2. Tap Copy app link.
3. Open Safari.
4. Paste the link into Safari’s address bar.
5. Tap Go.
6. If a Share button—a square with an arrow pointing up—is visible, tap it and continue at step 9.
7. Otherwise, tap the ⋯ button at the bottom of the screen.
8. Tap Share.
9. Scroll the list of options down by swiping up. Add to Home Screen sits below the row of apps and is easy to miss.
10. Tap Add to Home Screen.
11. If Add to Home Screen is missing, scroll to the very bottom of the list.
12. Tap Edit Actions.
13. Tap the green + beside Add to Home Screen.
14. Tap Done.
15. Scroll the list of options down again.
16. Tap Add to Home Screen.
17. If an Open as Web App switch appears, leave it on. Turning it off creates a plain bookmark and you will get no notifications. On older iPhones (iOS 18 and earlier) there is no switch; skip this step.
18. Tap Add.
19. Open ER Schedule from its new Home Screen icon.
20. Sign in with the same personal email.

iPad:
1. Open Add ER Schedule. You can find it on the screen after your Invite or in Settings.
2. Tap Copy app link.
3. Open Safari.
4. Paste the link into Safari’s address bar.
5. Tap Go.
6. Tap the ⋯ button at the top of the screen.
7. Tap View More.
8. If Add to Home Screen is visible, tap it and continue at step 14. There is no Share step on iPad.
9. Otherwise, scroll to the bottom of the list.
10. Tap Edit Actions.
11. Tap the green + beside Add to Home Screen.
12. Tap Done.
13. Tap Add to Home Screen.
14. If an Open as Web App switch appears, leave it on. Turning it off creates a plain bookmark and you will get no notifications. It is fine if there is no switch.
15. Tap Add.
16. Open ER Schedule from its new Home Screen icon.
17. Sign in with the same personal email.

Android Chrome:
1. Open Add ER Schedule.
2. Tap Copy app link.
3. Open Chrome itself—not a browser inside another app.
4. Paste the link into Chrome’s address bar.
5. Tap Go.
6. Tap the ⋮ button to the right of the address bar.
7. Tap Install and create shortcut.
8. Choose Install. Do not choose Create shortcut: shortcuts just open Chrome again.
9. Open ER Schedule from its new icon.
If Chrome offers to install by itself, accept. If it never offers, use the menu—Chrome stops offering for up to 90 days after you dismiss it once. If Install is greyed out, use Create shortcut; on Android, notifications work whether or not the app is installed.

Installation always needs your confirmation.''';

const iphoneNotificationInstallHint =
    'On iPhone or iPad, open Add ER Schedule in Settings and follow its Home Screen steps before allowing notifications. A browser bookmark cannot receive notifications; Web Push requires iOS or iPadOS 16.4 or later.';

const computerInstallFallbackGuidance =
    'On iPhone and iPad, follow the phone steps even if no Install button appears—Safari never offers to install for you, and a bookmark will not deliver notifications. On a computer, if your browser offers no install action, bookmarking the ordinary app link is fine.';
