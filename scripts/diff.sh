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
    || git fetch --no-tags --depth=1 origin "+refs/tags/${ref}:refs/tags/${ref}" \
    || git fetch --no-tags --depth=1 origin "$ref" \
    || { echo "ci-diff-changed: unable to resolve base ref [${BASE_REF}]" >&2; exit 1; }
  # The refspec fetches above create remote-tracking/tag refs; re-point
  # BASE_REF at the resolved SHA so shorthands (bare branches, tags) work.
  BASE_REF="$(git rev-parse --verify --quiet "refs/remotes/origin/${ref}" \
    || git rev-parse --verify --quiet "refs/tags/${ref}" \
    || git rev-parse --verify --quiet "$BASE_REF")"
fi

# Deepen until a merge base exists (bounded at 500 additional commits).
if ! git merge-base "$BASE_REF" HEAD >/dev/null 2>&1; then
  for _ in 1 2 3 4 5; do
    git fetch --deepen=100 --no-tags origin >/dev/null 2>&1 || true
    git merge-base "$BASE_REF" HEAD >/dev/null 2>&1 && break
  done
fi

if ! git merge-base "$BASE_REF" HEAD >/dev/null 2>&1; then
  # Unrelated histories (squash-merged PRs, force-pushed bases): no merge base
  # exists at any depth. Fall back to the previous commit, loudly.
  echo "ci-diff-changed: no merge base with [${BASE_REF}]; falling back to HEAD~1" >&2
  if git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    RAW_DIFF=$(git -c core.quotePath=false -c diff.renames=false diff --name-only --diff-filter=ACMRT HEAD~1)
  else
    # First commit of the branch: every tracked file is "added".
    RAW_DIFF=$(git -c core.quotePath=false -c diff.renames=false diff --name-only --diff-filter=ACMRT \
      "$(git hash-object -t tree /dev/null)")
  fi
elif RAW_DIFF=$(git -c core.quotePath=false -c diff.renames=false diff --name-only --diff-filter=ACMRT "${BASE_REF}...HEAD"); then
  :
else
  echo "ci-diff-changed: diff against [${BASE_REF}] failed; falling back to HEAD~1" >&2
  if git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    RAW_DIFF=$(git -c core.quotePath=false -c diff.renames=false diff --name-only --diff-filter=ACMRT HEAD~1)
  else
    RAW_DIFF=$(git -c core.quotePath=false -c diff.renames=false diff --name-only --diff-filter=ACMRT \
      "$(git hash-object -t tree /dev/null)")
  fi
fi

if [ -n "$PATTERN" ]; then
  # rc 0 = matches; rc 1 = no matches; anything else = invalid regex → hard error.
  set +e
  FILTERED=$(printf '%s\n' "$RAW_DIFF" | grep -E -- "$PATTERN")
  rc=$?
  set -e
  if [ "$rc" -gt 1 ]; then
    echo "ci-diff-changed: invalid pattern [${PATTERN}]" >&2
    exit 2
  fi
  [ "$rc" -eq 0 ] || FILTERED=""
else
  FILTERED="$RAW_DIFF"
fi

JSON_FILES=$(printf '%s\n' "$FILTERED" | sed '/^$/d' | jq -R -s -c 'split("\n")[:-1]')

if [ -z "$JSON_FILES" ] || [ "$JSON_FILES" = '[]' ]; then
  printf 'changed_files=[]\n' >>"$GITHUB_OUTPUT"
  printf 'has_changes=false\n' >>"$GITHUB_OUTPUT"
else
  printf 'changed_files=%s\n' "$JSON_FILES" >>"$GITHUB_OUTPUT"
  printf 'has_changes=true\n' >>"$GITHUB_OUTPUT"
fi
