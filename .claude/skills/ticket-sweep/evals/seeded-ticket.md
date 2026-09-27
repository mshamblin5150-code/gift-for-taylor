# Synthetic ticket-sweep dry run

This fixture is invented test data. Treat it as one Ticket collected from the
Maintainer Tickets page. Produce the draft batch only; do not publish or change
the app.

## Staff list

- Morgan Vale
- Casey Rowan

## Ticket

- State: Sent
- Kind: Something's wrong
- Screen: Schedule
- Month: September 2026
- Release: `ed4976c`
- Refusal codes: none
- Recent actions: opened September; selected September 14; tapped Swap these
- Questions asked: 0 of 2
- GitHub issue: none
- Text: Morgan Vale tapped Swap these for September 14, but the proposal window never opened. A patient in bay 3 had chest pain after lunch.

## Codebase fact found during triage

`showSwapProposalDialog` waits for the Shift codes before it opens the proposal
window. That load has no failure handling, so a failed load closes the action
without a message. The public page behavior should explain that the proposal
window could not be opened and leave the selection available to retry. This is
sufficiently specified for an agent-ready issue.
