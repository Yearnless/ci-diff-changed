# ci-diff-changed

**Ultra-lightweight composite GitHub Action** that reports which files changed between a base ref and `HEAD` — as a JSON array you can gate CI steps on.

- No Docker image, no Node runtime — pure `bash` + `git` + `jq` (preinstalled on GitHub-hosted Linux runners)
- Handles shallow clones: auto-fetches the base ref and deepens history until a merge base exists
- Regex filtering for monorepo-style path gating
- ~80 lines of shell you can read in one sitting

## Usage

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # full history guarantees a merge base
      - uses: noble2I/ci-diff-changed@v1
        id: diff
        with:
          base-ref: origin/main
          pattern: '\.(ts|js|json)$'
      - name: Run tests only when code changed
        if: steps.diff.outputs.has_changes == 'true'
        env:
          CHANGED_FILES: ${{ steps.diff.outputs.changed_files }}
        run: |
          echo "Changed: $CHANGED_FILES"
          npm test
```

## Inputs

| Input | Default | Description |
| :--- | :--- | :--- |
| `base-ref` | `origin/main` | Base commit, branch, or tag to compare against. Bare branches (`main`) and tags (`v1.2.3`) are fetched and resolved automatically. |
| `pattern` | *(empty)* | ERE regex (`grep -E`). Only matching paths are included. Empty = all files. An **invalid regex fails the step** rather than silently matching nothing. |

## Outputs

| Output | Description |
| :--- | :--- |
| `changed_files` | JSON-encoded string array of matching changed file paths. |
| `has_changes` | `"true"` if at least one file matched, otherwise `"false"`. |

## Semantics

- Added, copied, modified, renamed, and type-changed files count (`--diff-filter=ACMRT`); deletions are excluded.
- A rename lists the **new** path only (rename detection is disabled, so a rename surfaces as add-new + delete-old).
- Paths are emitted unquoted (`core.quotePath=false`), so non-ASCII names arrive verbatim. Paths containing embedded newlines are not supported.
- If no merge base exists at any fetch depth (squash-merged PRs, unrelated histories), the action falls back to a diff against `HEAD~1` with a stderr warning; on a single-commit branch it diffs against the empty tree (every tracked file counts as added).
- An unresolvable `base-ref` fails the step.

## Notes

- Run this action **after** `actions/checkout`. `fetch-depth: 0` (or `>= 50`) is recommended; the action still tries to fetch the base ref and deepen automatically for shallow clones.
- Requires `bash`, `git`, and `jq` — all preinstalled on `ubuntu-latest`.

## Security

Diff file paths can come from untrusted PRs. When consuming `changed_files` inside a `run:` step, always pass it through `env:` (as shown above) — never inline `${{ }}` interpolation into a script. Inputs are passed via `env:`, never interpolated into the script body.

## Local development

```bash
bash scripts/smoke.sh
```

Spins up throwaway git repositories and exercises every `diff.sh` scenario: unfiltered diff, regex filter, paths with spaces, renames, no-changes, first-commit fallback, unresolvable base ref, invalid regex, and tag base refs.

## License

MIT
