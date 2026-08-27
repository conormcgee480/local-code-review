# Local code review

A reusable GitHub Copilot skill for a repeatable, static, local review of the current
git branch against the repository's default branch — no builds, no test runs.

It is project-agnostic: any team on any repo can install it and use the same review
process. Team-specific rules live in `references/CODE_REVIEW_LEARNINGS.md`, which ships
empty for each team to grow over time.

## Quick start

```bash
git clone https://github.com/conormcgee480/local-code-review.git
cd local-code-review
./install-skill.sh
```

Then, in GitHub Copilot Chat or the Copilot CLI, run `/local-code-review` from the repo
you want reviewed.

Requires GitHub Copilot plus `bash` and `git` on your PATH (macOS/Linux). After pulling
updates to this repo, re-run `./install-skill.sh` — the installed copy does not auto-sync.
If you already have a skill named `local-code-review` in `~/.copilot/skills/`, the
installer overwrites it.

## Contents

| Path | Purpose |
| ---- | ------- |
| `SKILL.md` | The skill definition and review procedure. |
| `scripts/collect-review-context.sh` | Collects the branch diff into `code_reviews/context/latest.json`. |
| `assets/report-template.md` | Mandatory output format for every review report. |
| `references/CODE_REVIEW_LEARNINGS.md` | Team-specific review rules (starts empty). |

## Install

From this folder, run:

```bash
./install-skill.sh
```

This copies the skill into `~/.copilot/skills/local-code-review`, which is the
copy Copilot actually uses. Re-run it whenever you pull changes or edit the skill locally.

Verify:

```bash
ls ~/.copilot/skills/local-code-review
```

## Run it

Just invoke it from the repo you want reviewed:

```text
/local-code-review
```

It resolves the working directory by default. The parameter is optional — use it to
point somewhere else:

```text
/local-code-review review this repo
/local-code-review review my-service
/local-code-review /Users/you/code/my-service
```

- **(nothing)** / **"review this repo"** / "this branch" / "here" — the folder open in VS Code.
- **a repo name** — an open workspace folder (or sibling) with that name.
- **an absolute path** — used as-is.

Whichever you use, the skill resolves it to one concrete folder and passes that to the
collector. The context is always written to `<that-folder>/code_reviews/context/latest.json`
— inside the workspace, where the skill can reliably read it.

**Confirmation:**

- **You passed a full absolute path** — no extra step; the review runs.
- **Bare invocation, "this repo", or a repo name** — before running anything, the skill
  posts one line:
  *"About to review the repository at `/path` — reply with a different absolute path or
  "review &lt;name&gt;" if that's wrong, otherwise anything to go ahead."*
  Any reply ("yes", "go", 👍, or just re-sending) starts the review; a path or repo name
  redirects it. This happens before the collector runs, so nothing touches the repo until
  you answer. No emoji.

The skill will:

- resolve the repository from what you said
- run the review-context collection script (the only terminal command it runs)
- generate a review report under `code_reviews/` in the target repository

`code_reviews/` is added to the target repo's `.gitignore` automatically.

## Optional VS Code setting

To avoid approving the helper script on every run, add to your VS Code settings:

```json
"chat.tools.terminal.autoApprove": {
	"/collect-review-context\\.sh/": true
}
```

This only affects the collector command's approval. The skill still asks you to confirm
the repository (the "About to review the repository at …" line) before it runs anything,
unless you passed a full absolute path.

## Adding team learnings

As your team finds recurring issues worth flagging, add rules to
`references/CODE_REVIEW_LEARNINGS.md` using the entry format in that file, then
re-run `./install-skill.sh`.
