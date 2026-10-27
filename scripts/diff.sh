#!/usr/bin/env bash
# ci-diff-changed core logic.
# Emits `changed_files` (JSON array) and `has_changes` ("true"/"false") to $GITHUB_OUTPUT.
# Requires bash, git, and jq.
set -euo pipefail

: "${GITHUB_WORKSPACE:=$PWD}"
: "${GITHUB_OUTPUT:=/dev/stdout}"
: "${BASE_REF:=origin/main}"
: "${PATTERN:=}"

cd "$GITHUB_WORKSPACE"

# A containerized runner may mount the workspace with different ownership
# ("detected dubious ownership"). Only touch global config if git is broken.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  git config --global --add safe.directory "$GITHUB_WORKSPACE" 2>/dev/null || true
fi

# Resolve the base ref, fetching it if the shallow clone is missing it.
if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1; then
  ref="${BASE_REF#origin/}"
  git fetch --no-tags --depth=1 origin "+refs/heads/${ref}:refs/remotes/origin/${ref}" \
    || git fetch --no-tags --depth=1 origin "$ref" \
    || { echo "ci-diff-changed: unable to resolve base ref [${BASE_REF}]" >&2; exit 1; }
fi

# Deepen until a merge base exists (bounded at 500 additional commits).
if ! git merge-base "$BASE_REF" HEAD >/dev/null 2>&1; then
  for _ in 1 2 3 4 5; do
    git fetch --deepen=100 --no-tags origin >/dev/null 2>&1 || true
    git merge-base "$BASE_REF" HEAD >/dev/null 2>&1 && break
  done
fi

if ! RAW_DIFF=$(git diff --name-only --diff-filter=ACMRT "${BASE_REF}...HEAD"); then
  echo "ci-diff-changed: diff against [${BASE_REF}] failed; falling back to HEAD~1" >&2
  RAW_DIFF=$(git diff --name-only --diff-filter=ACMRT HEAD~1)
fi

if [ -n "$PATTERN" ]; then
  FILTERED=$(printf '%s\n' "$RAW_DIFF" | grep -E -- "$PATTERN" || true)
else
  FILTERED="$RAW_DIFF"
fi

JSON_FILES=$(printf '%s\n' "$FILTERED" | sed '/^$/d' | jq -R -s -c 'split("\n")[:-1]')

if [ -z "$JSON_FILES" ] || [ "$JSON_FILES" = "[]" ]; then
  printf 'changed_files=[]\n' >>"$GITHUB_OUTPUT"
  printf 'has_changes=false\n' >>"$GITHUB_OUTPUT"
else
  printf 'changed_files=%s\n' "$JSON_FILES" >>"$GITHUB_OUTPUT"
  printf 'has_changes=true\n' >>"$GITHUB_OUTPUT"
fi
