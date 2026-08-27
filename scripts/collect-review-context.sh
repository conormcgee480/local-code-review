#!/usr/bin/env bash

set -euo pipefail

MAX_DIFF_BYTES=400000      # 400 KB - monolithic unified diff cap
MAX_FILE_DIFF_BYTES=60000  # 60 KB cap per individual file diff
MAX_FILE_BUDGET=500000     # 500 KB total budget for all fileDiffs entries combined
MAX_DIFF_FILES=1000        # Max files changed allowed in review scope
MAX_DIFF_LINES=50000       # Max total changed lines (adds + deletes)

# Paths excluded from diffs to reduce noise.
# Add project-specific generated or snapshot files here as needed.
DIFF_EXCLUDES=(
  ':!package-lock.json'
  ':!yarn.lock'
  ':!pnpm-lock.yaml'
)

extract_package_lock_resolved_entries() {
  local diff_text="${1-}"
  printf '%s\n' "$diff_text" | grep -E '^[+-][[:space:]]*"resolved":' || true
}

json_escape() {
  local value="${1-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

truncate_diff() {
  local value="${1-}"
  if [[ ${#value} -gt $MAX_DIFF_BYTES ]]; then
    printf '%s' "${value:0:$MAX_DIFF_BYTES}"$'\n[DIFF TRUNCATED] Monolithic diff stream exceeded the configured size limit.'
  else
    printf '%s' "$value"
  fi
}

print_line() {
  printf '%s\n' "$1" >&2
}

print_block() {
  local block="${1-}"
  if [[ -n "$block" ]]; then
    printf '%s\n' "$block" >&2
  fi
}

repo_path="${1:-$PWD}"
cd "$repo_path"
invocation_dir="$(pwd)"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo 'ERROR: Target is not a git repository' >&2
  exit 1
}

branch=$(git branch --show-current)

if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "BRANCH_GUARD_FAILED: You are on $branch. Check out the feature branch you want to review and run /local-code-review again."
  exit 1
fi

# Primary context file: written under the directory the skill actually passed
# in (the VS Code workspace folder). That path is always inside the workspace,
# so the skill's file-reader can open it. A second copy goes under the repo
# root when that differs, so a repo-root reader also finds it.
primary_context_file="$invocation_dir/code_reviews/context/latest.json"
root_context_file="$repo_root/code_reviews/context/latest.json"
mkdir -p "$(dirname "$primary_context_file")" "$(dirname "$root_context_file")"

# Announce the resolved locations on stdout up front, so the skill can still
# find the context even if only the first line of output survives.
printf 'RESOLVED_REPO_ROOT: %s\n' "$repo_root"
printf 'CONTEXT_JSON: %s\n' "$primary_context_file"

if ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
  base_ref=${ref#refs/remotes/}
  fetch_branch=${ref#refs/remotes/origin/}
elif git show-ref --verify --quiet refs/remotes/origin/main; then
  base_ref='origin/main'
  fetch_branch='main'
elif git show-ref --verify --quiet refs/remotes/origin/master; then
  base_ref='origin/master'
  fetch_branch='master'
elif git show-ref --verify --quiet refs/heads/main; then
  base_ref='main'
  fetch_branch=''
elif git show-ref --verify --quiet refs/heads/master; then
  base_ref='master'
  fetch_branch=''
else
  echo 'ERROR: No base branch found' >&2
  exit 1
fi

print_line "Current branch: $branch"
print_line "Repo root: $repo_root"
print_line "Base ref: $base_ref"

if [[ -n "$fetch_branch" ]]; then
  print_line "Fetch command: git fetch --no-tags origin $fetch_branch:refs/remotes/origin/$fetch_branch"
  git fetch --no-tags origin "$fetch_branch:refs/remotes/origin/$fetch_branch"
  fetch_result='success'
else
  fetch_result='skipped (local base ref)'
fi

print_line "Fetch result: $fetch_result"

merge_base=$(git merge-base HEAD "$base_ref")
head_commit=$(git rev-parse HEAD)
commits_ahead=$(git rev-list --count "$merge_base..HEAD")
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

working_tree_status=$(git status --short)
changed_files=$(git diff --name-only "$merge_base" -- . "${DIFF_EXCLUDES[@]}")
diff_stat=$(git diff --stat "$merge_base" -- . "${DIFF_EXCLUDES[@]}")
changed_file_count=$(git diff --name-only "$merge_base" -- . "${DIFF_EXCLUDES[@]}" | sed '/^$/d' | wc -l | tr -d ' ')
changed_line_count=$(git diff --numstat "$merge_base" -- . "${DIFF_EXCLUDES[@]}" | awk '{ if ($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/) s += $1 + $2 } END { print s + 0 }')
committed_changed_files=$(git diff --name-only "$merge_base..HEAD" -- . "${DIFF_EXCLUDES[@]}")
committed_diff_stat=$(git diff --stat "$merge_base..HEAD" -- . "${DIFF_EXCLUDES[@]}")
committed_unified_diff=$(truncate_diff "$(git diff --unified=8 "$merge_base..HEAD" -- . "${DIFF_EXCLUDES[@]}")")
working_tree_changed_files=$(git diff --name-only HEAD -- . "${DIFF_EXCLUDES[@]}")
working_tree_diff_stat=$(git diff --stat HEAD -- . "${DIFF_EXCLUDES[@]}")
working_tree_unified_diff=$(truncate_diff "$(git diff --unified=8 HEAD -- . "${DIFF_EXCLUDES[@]}")")
untracked_files=$(git ls-files --others --exclude-standard)
untracked_diff=$(
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    git diff --no-index --unified=8 -- /dev/null "$file" || true
  done < <(git ls-files --others --exclude-standard)
)
unified_diff=$(truncate_diff "$(git diff --unified=8 "$merge_base" -- . "${DIFF_EXCLUDES[@]}")")
package_lock_resolved_entries=$(extract_package_lock_resolved_entries "$(git diff --unified=0 "$merge_base" -- package-lock.json 2>/dev/null || true)")

diff_files_limit_exceeded='false'
if [[ "$changed_file_count" -gt "$MAX_DIFF_FILES" ]]; then
  diff_files_limit_exceeded='true'
fi

diff_lines_limit_exceeded='false'
if [[ "$changed_line_count" -gt "$MAX_DIFF_LINES" ]]; then
  diff_lines_limit_exceeded='true'
fi

diff_truncated='false'
if [[ "$unified_diff" == *"[DIFF TRUNCATED"* ]] || [[ "$committed_unified_diff" == *"[DIFF TRUNCATED"* ]] || [[ "$working_tree_unified_diff" == *"[DIFF TRUNCATED"* ]] || [[ "$diff_files_limit_exceeded" == 'true' ]] || [[ "$diff_lines_limit_exceeded" == 'true' ]]; then
  diff_truncated='true'
fi

diff_limit_reasons=''
if [[ "$diff_files_limit_exceeded" == 'true' ]]; then
  diff_limit_reasons+="MAX_DIFF_FILES exceeded (${changed_file_count} > ${MAX_DIFF_FILES})"$'\n'
fi
if [[ "$diff_lines_limit_exceeded" == 'true' ]]; then
  diff_limit_reasons+="MAX_DIFF_LINES exceeded (${changed_line_count} > ${MAX_DIFF_LINES})"$'\n'
fi
if [[ "$unified_diff" == *"[DIFF TRUNCATED"* ]] || [[ "$committed_unified_diff" == *"[DIFF TRUNCATED"* ]]; then
  diff_limit_reasons+="MAX_DIFF_BYTES exceeded for monolithic diff"$'\n'
fi
if [[ "$working_tree_unified_diff" == *"[DIFF TRUNCATED"* ]]; then
  diff_limit_reasons+="MAX_DIFF_BYTES exceeded for working tree diff"$'\n'
fi
diff_limit_reasons="${diff_limit_reasons%$'\n'}"

# ── Per-file diff collection ──────────────────────────────────────────────────
# Each changed file gets its own diff entry, capped at MAX_FILE_DIFF_BYTES.
# Files are included in order until MAX_FILE_BUDGET is exhausted; any remaining
# files are listed in excludedFromFileDiffs.
#
# This structure lets the reviewer work file-by-file on large PRs instead of
# hitting a single hard truncation midway through the monolithic diff.

file_diffs_json='['
file_diffs_sep=''
file_budget_used=0
excluded_from_file_diffs=''
file_index=0

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  file_index=$(( file_index + 1 ))

  if (( file_index > MAX_DIFF_FILES )); then
    excluded_from_file_diffs+="$file"$'\n'
    continue
  fi

  raw_diff=$(git diff --unified=8 "$merge_base" -- "$file" 2>/dev/null || true)
  raw_bytes=${#raw_diff}

  # Cap this individual file's diff at the per-file limit
  if [[ $raw_bytes -gt $MAX_FILE_DIFF_BYTES ]]; then
    file_diff="${raw_diff:0:$MAX_FILE_DIFF_BYTES}"$'\n[FILE DIFF TRUNCATED: exceeded 60 KB per-file limit]'
    file_truncated='true'
  else
    file_diff="$raw_diff"
    file_truncated='false'
  fi

  entry_size=${#file_diff}

  # Drop to excluded list if the total budget would be exceeded
  if (( file_budget_used + entry_size > MAX_FILE_BUDGET )); then
    excluded_from_file_diffs+="$file"$'\n'
    continue
  fi

  file_budget_used=$(( file_budget_used + entry_size ))

  file_diffs_json+="${file_diffs_sep}"$'\n'
  file_diffs_json+='{"filename":"'"$(json_escape "$file")"'","bytes":'"$raw_bytes"',"truncated":'"$file_truncated"',"diff":"'"$(json_escape "$file_diff")"'"}'
  file_diffs_sep=','
done < <(git diff --name-only "$merge_base" -- . "${DIFF_EXCLUDES[@]}")

file_diffs_json+=$'\n]'

# Strip trailing newline from the excluded list
excluded_from_file_diffs="${excluded_from_file_diffs%$'\n'}"

print_line "Merge base: $merge_base"
print_line "Head commit: $head_commit"
print_line "Commits ahead of base: $commits_ahead"
print_line "Changed file count: $changed_file_count (limit: $MAX_DIFF_FILES)"
print_line "Changed line count: $changed_line_count (limit: $MAX_DIFF_LINES)"
print_line "Diff files limit exceeded: $diff_files_limit_exceeded"
print_line "Diff lines limit exceeded: $diff_lines_limit_exceeded"
print_line "Diff truncated: $diff_truncated"
print_line "Per-file budget used: $file_budget_used / $MAX_FILE_BUDGET bytes"
print_line ""
print_line "Working tree status:"
print_block "$working_tree_status"
print_line ""
print_line "Changed files:"
print_block "$changed_files"
print_line ""
print_line "Diff stat:"
print_block "$diff_stat"
print_line ""
print_line "Untracked files:"
print_block "$untracked_files"
print_line ""
print_line "Untracked diff:"
print_block "$untracked_diff"
print_line ""
print_line "package-lock resolved entries:"
print_block "$package_lock_resolved_entries"
print_line ""
print_line "Unified diff:"
print_block "$unified_diff"

context_tmp=$(mktemp "$(dirname "$primary_context_file")/latest.json.XXXXXX")
trap 'rm -f "$context_tmp"' EXIT

cat > "$context_tmp" <<EOF
{
  "generatedAt": "$(json_escape "$generated_at")",
  "repoPath": "$(json_escape "$repo_path")",
  "repoRoot": "$(json_escape "$repo_root")",
  "branch": "$(json_escape "$branch")",
  "baseRef": "$(json_escape "$base_ref")",
  "fetchBranch": "$(json_escape "$fetch_branch")",
  "fetchResult": "$(json_escape "$fetch_result")",
  "mergeBase": "$(json_escape "$merge_base")",
  "headCommit": "$(json_escape "$head_commit")",
  "commitsAheadOfBase": "$(json_escape "$commits_ahead")",
  "maxDiffBytes": $MAX_DIFF_BYTES,
  "maxDiffFiles": $MAX_DIFF_FILES,
  "maxDiffLines": $MAX_DIFF_LINES,
  "maxFileDiffBytes": $MAX_FILE_DIFF_BYTES,
  "maxFileBudget": $MAX_FILE_BUDGET,
  "changedFileCount": $changed_file_count,
  "changedLineCount": $changed_line_count,
  "diffFilesLimitExceeded": $diff_files_limit_exceeded,
  "diffLinesLimitExceeded": $diff_lines_limit_exceeded,
  "diffLimitReasons": "$(json_escape "$diff_limit_reasons")",
  "diffTruncated": $diff_truncated,
  "workingTreeStatus": "$(json_escape "$working_tree_status")",
  "changedFiles": "$(json_escape "$changed_files")",
  "diffStat": "$(json_escape "$diff_stat")",
  "committedChangedFiles": "$(json_escape "$committed_changed_files")",
  "committedDiffStat": "$(json_escape "$committed_diff_stat")",
  "committedUnifiedDiff": "$(json_escape "$committed_unified_diff")",
  "workingTreeChangedFiles": "$(json_escape "$working_tree_changed_files")",
  "workingTreeDiffStat": "$(json_escape "$working_tree_diff_stat")",
  "workingTreeUnifiedDiff": "$(json_escape "$working_tree_unified_diff")",
  "untrackedFiles": "$(json_escape "$untracked_files")",
  "untrackedDiff": "$(json_escape "$untracked_diff")",
  "packageLockResolvedEntries": "$(json_escape "$package_lock_resolved_entries")",
  "unifiedDiff": "$(json_escape "$unified_diff")",
  "fileDiffs": $file_diffs_json,
  "excludedFromFileDiffs": "$(json_escape "$excluded_from_file_diffs")"
}
EOF

mv "$context_tmp" "$primary_context_file"
trap - EXIT

# Second copy under the repo root, when the invocation directory was not the
# repo root itself. Both paths are inside the repo, so the skill can read
# whichever one matches the folder it passed in.
if [[ "$root_context_file" != "$primary_context_file" ]]; then
  root_tmp=$(mktemp "${root_context_file}.XXXXXX")
  cp "$primary_context_file" "$root_tmp"
  mv "$root_tmp" "$root_context_file"
fi

printf 'CONTEXT_JSON: %s\n' "$primary_context_file"
printf 'DONE\n'
