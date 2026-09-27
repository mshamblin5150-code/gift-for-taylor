# GitHub and release evidence

Use `gh` from this repository. GitHub facts are public tracker evidence; Ticket
facts still come only from the app.

## Issue disposition

Read the linked issue and its closing pull requests:

```powershell
gh issue view <number> --json state,stateReason,labels,closedAt,closedByPullRequestsReferences,url
```

A Won't-do close note requires `state: CLOSED` and the canonical `wontfix`
label. A merely closed issue is not enough.

## Fix and Pages deployment

For each closing pull request, read its merge commit:

```powershell
gh pr view <number> --json state,mergedAt,mergeCommit,url
```

Then find the GitHub Pages workflow run for that merge commit:

```powershell
gh run list --workflow pages.yml --commit <merge-commit-sha> --json status,conclusion,headSha,url,createdAt
```

Done requires a run whose `headSha` is the merge commit, `status` is
`completed`, and `conclusion` is `success`. If the fix reached `main` through a
later commit, prove ancestry with `git merge-base --is-ancestor <fix-sha>
<deployed-head-sha>` and inspect the successful Pages run for that deployed
head. Treat absent or ambiguous evidence as **Nothing yet**.

Immediately before an approved close, repeat the issue and deployment checks;
the draft may have gone stale while waiting for approval.
