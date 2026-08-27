---
name: local-code-review
description: Perform a local static code review of the current branch against origin/main or origin/master, apply CODE_REVIEW_LEARNINGS, and save the report to code_reviews/. Use for branch reviews, pre-PR reviews, and quick static diff reviews.
argument-hint: e.g. "review this repo", a repo name, or an absolute path
---

# Local code review

Use this skill to review the current git branch against the repository default branch without running builds or tests.

## When to use

- Review a feature branch before opening a pull request.
- Produce a local review report for a ticket or change set.
- Run a quick static diff review when command budget should stay low.

## Constraints

- Execute only one terminal command: the helper script. No other terminal commands may be run.
- **The only files this skill may open with a Read/file tool are:** `<review-folder>/code_reviews/context/latest.json` (the folder passed to the collector), `<repo-root>/.gitignore`, [CODE_REVIEW_LEARNINGS](./references/CODE_REVIEW_LEARNINGS.md), and [report-template](./assets/report-template.md). Pass fully-expanded absolute paths inside the workspace — the file tool does not expand `$HOME` or `~` and cannot read outside the workspace folder. Before calling a read tool, check the path against this list; if it isn't on the list, do not make the call. This applies to every file changed in the diff, with no exceptions for "just confirming" a finding, verifying a line number, or checking surrounding context — the unified diff already contains everything needed.
- If a finding feels like it needs a source file open to confirm, that impulse is the signal to stop, not a reason to proceed — write the finding as an observation based on the diff, or note the limitation in the report, but do not read the file.
- After the script runs, always read `<review-folder>/code_reviews/context/latest.json` using the Read file tool — regardless of whether the terminal returned output. "Failed to retrieve command output" does not mean the script failed and does not move the file; it is at that path. See Procedure step 3, including the retry rule.
- Only ask the user to paste the file manually if the Read file tool returns a file-not-found error.
- Do not fall back to individual git commands under any circumstances.
- Do not read individual source files. The unified diff in the JSON context file is sufficient context for the review.
- Do not run Maven, Gradle, npm, Node, test suites, or build commands.
- Do not run git log, git show, cat, or any other command after the script completes.
- Do not fall back to individual git commands under any circumstances.

## Inputs

- Current branch: treat the checked-out branch as the feature branch.
- Optional user input: which repo to review ("this repo" / a repo name / an absolute path), plus any ticket slug, short description, or review focus.

## Repository selection

Always resolve **one concrete absolute folder** for the target repository and always pass it to the collector as its argument. Never run the collector with no argument.

Resolve the folder in this priority order:

1. **An absolute path in the user's message** — e.g. `/Users/you/code/my-service`. Use it.
2. **"review this repo" / "this branch" / "here" / a bare invocation** — the folder currently open in VS Code (the workspace folder). In the Copilot CLI, the current working directory.
3. **A repo name** — "review my-service" → the open workspace folder (or a sibling folder) with that name.
4. **None of the above yields a folder** — ask the user for the repository's absolute path and wait.

Do not pick the repository from the active editor file path or open tabs. Reuse a resolved folder for later runs in the same conversation unless the user names a different one.

## Procedure

1. Resolve the absolute folder per **Repository selection**, then confirm it **before running anything**:
   - **Rule 1 (the user typed a full absolute path)** — no confirmation needed; go to step 2.
   - **Rule 2, 3, or 4** — post exactly this one line, no emoji, and **stop for the user's reply**:
     `About to review the repository at <absolute-folder> — reply with a different absolute path or "review <name>" if that's wrong, otherwise anything to go ahead.`
     - Treat **any** reply as "go ahead" and proceed to step 2 with `<absolute-folder>` — unless the reply gives a different absolute path or names a different repo, in which case re-resolve and use that. The user does not have to type a specific word; "yes", "y", "go", "ok", a thumbs up, or just re-sending all mean proceed.
   - Nothing has run at this point (no collector, no review, no files touched), so this stop is safe to be resumed. When you continue — or if the skill is re-entered from the top — take the user's "ok" or the path they gave from the conversation and proceed from step 2. Do **not** ask again, and do **not** repeat any later step.
2. Run the collector: `bash $HOME/.copilot/skills/local-code-review/scripts/collect-review-context.sh <absolute-folder>`, always with the confirmed folder as the argument. Once it runs, check the output:
   - `BRANCH_GUARD_FAILED:` → stop and respond only with: "You are on `main` or `master`. Please check out the feature branch you want reviewed and run `/local-code-review` again."
   - `ERROR: Target is not a git repository` → the folder is not a git repo; stop, ask the user for the correct absolute path, and re-run this step.
3. **Read the context JSON with the Read file tool.** The file is at **`<absolute-folder>/code_reviews/context/latest.json`** — the folder you just passed to the collector, with `/code_reviews/context/latest.json` appended. It is inside that folder (and inside the VS Code workspace), so the file tool can open it. Read it **regardless of the terminal output** — "Failed to retrieve command output" or no visible output does **not** mean the run failed or that the file is elsewhere; the path is still `<absolute-folder>/code_reviews/context/latest.json`.
   - Pass a fully-expanded absolute path to the Read tool — never a path containing `$HOME`, `~`, or any shell variable, and never a location outside the workspace.
   - If the first read returns not-found, the atomic rename may still be settling: retry the same path once before concluding anything.
   - The collector also prints `RESOLVED_REPO_ROOT: <path>` and `CONTEXT_JSON: <path>` marker lines. If any survived and the path above failed both times, read the `CONTEXT_JSON:` path instead (it may differ when the folder you passed was not the repo root).
   - Only if every attempt genuinely fails, or the JSON is empty/malformed: treat collection as failed — do not review, say so, and ask the user for the repository's absolute path before re-running.

   Take `repoRoot`, `branch`, `baseRef`, `headCommit`, and `changedFileCount` from the JSON and use `repoRoot` as `<repo-root>` for every later step.
4. State what you resolved in **one line, no emoji**, then continue to step 5 **in the same turn** — the repository was already confirmed in step 1, so do not stop or wait here:

   `Resolved <repoRoot> — branch <branch> vs <baseRef>, <changedFileCount> file(s) changed. Reviewing now.`

   Run the collector at most twice per invocation (once, plus one re-run only if a read genuinely failed). Do the review and write the report exactly once (steps 7–10). After the report is written, do not review again, re-run the collector, or write the report again.
5. Update `.gitignore` as a **standalone single-file edit** — never combined with the report or any other file in one patch. If `<repo-root>/.gitignore` exists and does not already list `code_reviews/`, append `code_reviews/` on its own new line and change nothing else. If it already lists `code_reviews/`, or no `.gitignore` exists, make no change at all. Complete and verify this edit before moving on to the report.
6. **Do not run any further terminal commands, and do not open any file outside the allow-list in Constraints.** Treat the JSON file as the complete review context. Do not read individual source files (even ones named in the diff, even to double-check a finding) or run git log, git show, cat, or any other repository-inspection commands. The only writes permitted from here are the `.gitignore` edit (step 5) and the report file (step 10), each as its own separate single-file operation — never one patch spanning both.
7. Perform the review **a single time**. If you have already produced findings or a report earlier in this invocation, do not redo it. Use the following fields from the JSON for the review:
   - `branch`, `baseRef`, `mergeBase`, `headCommit` — for report metadata
   - `changedFiles`, `diffStat`, `workingTreeStatus`, `untrackedFiles` — for the files reviewed section
   - `committedUnifiedDiff`, `workingTreeUnifiedDiff`, `untrackedDiff` — for supplementary detail
   - Lockfiles will be intentionally excluded from the general diff collection to reduce noise. Do not raise findings based only on lockfile absence.
   - `packageLockResolvedEntries` contains only added or removed `"resolved"` lines from `package-lock.json`. Use this field only for lockfile-specific registry-policy checks from `CODE_REVIEW_LEARNINGS`; otherwise continue to ignore lockfile noise.

   **Choose the right diff source based on size:**

   - **`diffTruncated` is `false`** — use `unifiedDiff` as the primary review source. This is the normal path for small-to-medium PRs.

    - **`diffTruncated` is `true`** — a monolithic diff stream exceeded 400,000 bytes (about 400 KB) and was cut off. Switch to a file-by-file review using `fileDiffs`:
       1. `fileDiffs` is an array of `{ filename, bytes, truncated, diff }` entries — one per changed file, each capped at 60,000 bytes (about 60 KB). Review them in sequence, producing findings as you go.
       2. If any entry has `truncated: true`, note in the report that the diff for that specific file was partially truncated.
       3. `excludedFromFileDiffs` lists any files that were dropped because the 500,000-byte total file-by-file budget (about 500 KB) was exhausted. For those files, fall back to whatever portion of `unifiedDiff` covers them, and note in the report that those files received only a partial review.
          4. Add a visible banner at the top of the Findings section:
               - Coverage complete: "⚠️ Large-diff mode used; reviewed file-by-file with complete coverage."
               - Coverage partial: "⚠️ Large-diff mode used; partial coverage because some file diffs were truncated or excluded."
8. Apply the project-specific rules in [CODE_REVIEW_LEARNINGS](./references/CODE_REVIEW_LEARNINGS.md).
9. Apply **verdict guardrails** before deciding status:
    - Evaluate coverage first when `diffTruncated` is `true`:
       - Coverage is **complete** when all changed files appear in `fileDiffs`, no file entry has `truncated: true`, and `excludedFromFileDiffs` is empty.
       - Coverage is **partial** when any file entry has `truncated: true` or `excludedFromFileDiffs` is non-empty.
    - Use verdicts consistently:
       - **Green**: no high/medium findings and coverage is complete (large-diff warning banner still required).
       - **Amber**: coverage is partial, uncertainty remains material, or medium-severity risk exists.
       - **Red**: confirmed high-severity defect(s).
    - Do **not** use Amber only because `diffTruncated` is true when coverage is complete.
10. Write the report — **once per invocation**, as delete-then-create, on the report file only (never bundled with the step 5 `.gitignore` edit or any other file):
    a. **Path:** `<repo-root>/code_reviews/<branch-name>-<YYYY-MM-DD>.md` — filesystem-safe branch name (replace `/` and any other unsafe character with `-`), e.g. `feature-loyalty-tiers-2026-08-27.md`.
    b. **Delete first.** If anything already exists at that path — your own report from earlier this turn, or a previous run's — delete the file. If your tools cannot delete, open it and replace its entire contents, keeping none of the old text. Do this even if you think you have not written it yet.
    c. **Create once.** Write the file with the complete report, formatted per [report-template](./assets/report-template.md) (formatting is mandatory), in a **single write**. Never append, never insert, never split it across more than one write.
    d. **Verify.** The finished file must contain exactly one report. If it has more than one (e.g. two `# ` title lines, two Verdict tables), delete it and write it once more, correctly.
    e. If a write is rejected or asks for a missing field, do not assume the file is unchanged — go back to step (b) (delete) and redo (c). Never recover by appending.
    f. The skill is now finished. Do not review again, re-run the collector, or write the report again in this invocation.
