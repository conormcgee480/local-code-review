# CODE_REVIEW_LEARNINGS

Use this file to capture project and organisation-specific code review rules over time.

This file starts empty. Each team using this skill should add their own rules as they
learn what is worth flagging in their codebases.

## How to use

- Add short, concrete rules that should influence future reviews.
- Prefer examples of bugs, regressions, and patterns worth flagging.
- Keep entries specific enough to apply consistently.

## Current guidance

- Use `/local-code-review` to invoke this workflow explicitly when you want a repeatable branch review that follows this skill's process.
- Prefer the explicit slash command over vague review prompts when consistency matters.
- A targeted `git fetch` that only refreshes remote-tracking refs for the review base branch is acceptable in this workflow and should be treated as low-risk repo metadata refresh, not as a working-tree modification.

## Suggested entry format

### Rule

- State the rule or recurring issue.

### Why it matters

- Explain the production, delivery, or maintenance risk.

### What to check

- Describe the signals that should trigger a comment.

### Example

- Add a short example if it helps future reviewers.

---

<!-- Add project-specific learnings below this line. -->
