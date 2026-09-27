# Draft contract

Return exactly one draft per Ticket. Use plain language and repeat no Ticket or
thread sentence verbatim.

## Decide the type

### Issue

Use when code and app evidence make the work sufficiently specified. Write an
agent-ready GitHub issue in this repository's style and select the applicable
canonical label from `docs/agents/triage-labels.md`. Its body must say **from a
Ticket** and contain the observed behavior, expected behavior, relevant
non-private context, acceptance checks, and evidence an implementing agent can
reproduce. Its context explicitly names the Ticket kind, screen, Month,
release, and refusal codes; use `none` or `not attached` when the app supplied
no value. It contains no sender name, Staff name, role, device, or patient
detail.

### Question

Use only after checking the app context and codebase leaves one fact that
changes the decision. Ask one plain-language question and give one likely
answer the sender can confirm with a tap. Use this type only when fewer than two
questions have already been asked. `needs-info` stays in the app and is not a
GitHub label or issue.

When two questions have already been asked, return **Nothing yet** and include
`Designer follow-up: Ask in person`.

### Close note

Read [github-evidence.md](github-evidence.md) before returning this type.

- **Done** requires a linked issue that is closed and a successful GitHub Pages
  deploy containing the fixing commit. Write a short note for a nurse about the
  behavior now live, without repository or deployment jargon.
- **Won't do** requires a linked issue closed with the canonical `wontfix`
  label. Explain the product reason in plain language.

If either proof is incomplete, return **Nothing yet**.

### Nothing yet

Use for an open issue, missing deployment evidence, the third would-be
question, or any state where no action is due. Give one line saying why. This
type has no approval and causes no mutation.

## Batch shape

Use this shape exactly so dry-run evals and the designer can audit a batch:

```text
## Ticket <private working key>
Staff-name match: yes|no
Patient detail: yes — Redact recommended|no
Draft type: Issue|Question|Close note|Nothing yet
### Draft
<the complete proposed issue, question plus suggested answer, close note, or one-line reason>
Approval: Pending|Not applicable
```

Use `Approval: Pending` for Issue, Question, and Close note. Use
`Approval: Not applicable` for Nothing yet.
