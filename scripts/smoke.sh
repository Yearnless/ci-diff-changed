#!/usr/bin/env bash
# Local end-to-end test of scripts/diff.sh against a throwaway git repository.
# Run with: bash scripts/smoke.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

git init -q -b main "$repo"
git -C "$repo" config user.email smoke@example.com
git -C "$repo" config user.name smoke
mkdir -p "$repo/src" "$repo/docs"

echo one >"$repo/src/a.ts"
echo one >"$repo/docs/b.md"
git -C "$repo" add -A
git -C "$repo" commit -qm 'first'

echo two >"$repo/src/a.ts"
echo new >"$repo/src/new.js"
echo doc >"$repo/docs/b.md"
git -C "$repo" add -A
git -C "$repo" commit -qm 'second'

run_diff() { # $1=BASE_REF $2=PATTERN $3=outfile
  BASE_REF="$1" PATTERN="$2" GITHUB_OUTPUT="$3" GITHUB_WORKSPACE="$repo" bash "$SCRIPT_DIR/diff.sh"
}

# 1. Unfiltered diff against HEAD~1
out1="$(mktemp)"
run_diff 'HEAD~1' '' "$out1"
files1="$(grep '^changed_files=' "$out1" | cut -d= -f2-)"
has1="$(grep '^has_changes=' "$out1" | cut -d= -f2-)"
[ "$has1" = 'true' ]
echo "$files1" | grep -q '"src/a.ts"'
echo "$files1" | grep -q '"src/new.js"'
echo "$files1" | grep -q '"docs/b.md"'

# 2. Regex-filtered diff (docs must drop out)
out2="$(mktemp)"
run_diff 'HEAD~1' '\.(ts|js)$' "$out2"
files2="$(grep '^changed_files=' "$out2" | cut -d= -f2-)"
echo "$files2" | grep -q '"src/a.ts"'
echo "$files2" | grep -q '"src/new.js"'
if echo "$files2" | grep -q 'docs/b.md'; then
  echo 'FAIL: docs/b.md leaked through the pattern filter' >&2
  exit 1
fi

# 3. No changes => has_changes=false and []
git -C "$repo" commit -q --allow-empty -m 'empty'
out3="$(mktemp)"
run_diff 'HEAD' '' "$out3"
[ "$(grep '^changed_files=' "$out3" | cut -d= -f2-)" = '[]' ]
[ "$(grep '^has_changes=' "$out3" | cut -d= -f2-)" = 'false' ]

# 4. JSON is machine-parseable (last element check)
echo "$files1" | jq -e 'type == "array" and length == 3' >/dev/null

echo 'smoke OK: all diff.sh scenarios passed'
