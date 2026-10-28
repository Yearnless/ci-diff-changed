#!/usr/bin/env bash
# Local end-to-end test of scripts/diff.sh against throwaway git repositories.
# Run with: bash scripts/smoke.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo="$(mktemp -d)"
repo2=""
trap 'rm -rf "$repo" "$repo2"' EXIT

git init -q -b main "$repo"
git -C "$repo" config user.email smoke@example.com
git -C "$repo" config user.name smoke
mkdir -p "$repo/src" "$repo/docs" "$repo/with space"

echo one >"$repo/src/a.ts"
echo one >"$repo/docs/b.md"
echo one >"$repo/with space/c file.js"
git -C "$repo" add -A
git -C "$repo" commit -qm 'first'

echo two >"$repo/src/a.ts"
echo new >"$repo/src/new.js"
echo doc >"$repo/docs/b.md"
git -C "$repo" add -A
git -C "$repo" commit -qm 'second'
git -C "$repo" tag v0

# A rename: with diff.renames=false this must surface as the new path only
# (old path shows as deleted and is filtered out by ACMRT).
git -C "$repo" mv "src/a.ts" "src/renamed.ts"
git -C "$repo" commit -qm 'rename'

# Touch a path containing spaces (quotePath=false must keep it verbatim).
echo three >"$repo/with space/c file.js"
echo doc2 >"$repo/docs/b.md"
git -C "$repo" add -A
git -C "$repo" commit -qm 'touch space + docs'

run_diff() { # $1=BASE_REF $2=PATTERN $3=outfile  (runs in $repo)
  BASE_REF="$1" PATTERN="$2" GITHUB_OUTPUT="$3" GITHUB_WORKSPACE="$repo" bash "$SCRIPT_DIR/diff.sh"
}

# 1. Unfiltered diff against HEAD~2 (the rename commit).
out1="$(mktemp)"
run_diff 'HEAD~2' '' "$out1"
files1="$(grep '^changed_files=' "$out1" | cut -d= -f2-)"
[ "$(grep '^has_changes=' "$out1" | cut -d= -f2-)" = 'true' ]
echo "$files1" | grep -q '"src/renamed.ts"'
if echo "$files1" | grep -q 'src/a.ts'; then
  echo 'FAIL: deleted old rename path leaked into results' >&2
  exit 1
fi

# 2. Regex-filtered diff; paths with spaces survive intact.
out2="$(mktemp)"
run_diff 'HEAD~1' '\.(ts|js)$' "$out2"
files2="$(grep '^changed_files=' "$out2" | cut -d= -f2-)"
echo "$files2" | grep -q '"with space/c file.js"'
if echo "$files2" | grep -q 'docs/b.md'; then
  echo 'FAIL: docs/b.md leaked through the pattern filter' >&2
  exit 1
fi
# 3. JSON is machine-parseable.
echo "$files2" | jq -e 'type == "array" and length == 1' >/dev/null

# 4. No changes => has_changes=false and [].
git -C "$repo" commit -q --allow-empty -m 'empty'
out3="$(mktemp)"
run_diff 'HEAD' '' "$out3"
[ "$(grep '^changed_files=' "$out3" | cut -d= -f2-)" = '[]' ]
[ "$(grep '^has_changes=' "$out3" | cut -d= -f2-)" = 'false' ]

# 5. First-commit repo (orphan branch, no HEAD~1, no merge base):
#    every tracked file counts as added via the empty-tree fallback.
repo2="$(mktemp -d)"
git init -q -b main "$repo2"
git -C "$repo2" config user.email smoke@example.com
git -C "$repo2" config user.name smoke
echo hello >"$repo2/only.txt"
git -C "$repo2" add -A
git -C "$repo2" commit -qm 'initial'
git -C "$repo2" checkout -q --orphan fresh
git -C "$repo2" rm -rqf .
echo orphan >"$repo2/orphan.txt"
git -C "$repo2" add -A
git -C "$repo2" commit -qm 'orphan'
out4="$(mktemp)"
BASE_REF='main' PATTERN='' GITHUB_OUTPUT="$out4" GITHUB_WORKSPACE="$repo2" bash "$SCRIPT_DIR/diff.sh"
[ "$(grep '^has_changes=' "$out4" | cut -d= -f2-)" = 'true' ]
grep '^changed_files=' "$out4" | cut -d= -f2- | grep -q '"orphan.txt"'

# 6. Unresolvable base ref must fail the step, not silently report no changes.
out5="$(mktemp)"
if BASE_REF='origin/nonexistent-branch' PATTERN='' GITHUB_OUTPUT="$out5" GITHUB_WORKSPACE="$repo2" \
  bash "$SCRIPT_DIR/diff.sh" 2>/dev/null; then
  echo 'FAIL: unresolvable base ref should exit non-zero' >&2
  exit 1
fi

# 7. Invalid regex must hard-fail, not silently yield no changes.
out6="$(mktemp)"
if BASE_REF='HEAD' PATTERN='[' GITHUB_OUTPUT="$out6" GITHUB_WORKSPACE="$repo" bash "$SCRIPT_DIR/diff.sh" 2>/dev/null; then
  echo 'FAIL: invalid pattern must exit non-zero' >&2
  exit 1
fi

# 8. Tag as base ref.
out7="$(mktemp)"
run_diff 'v0' '' "$out7"
[ "$(grep '^has_changes=' "$out7" | cut -d= -f2-)" = 'true' ]
grep '^changed_files=' "$out7" | cut -d= -f2- | grep -q '"src/renamed.ts"'
grep '^changed_files=' "$out7" | cut -d= -f2- | grep -q '"with space/c file.js"'

echo 'smoke OK: all diff.sh scenarios passed'
