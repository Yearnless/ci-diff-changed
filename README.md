# ci-diff-changed

**Ultra-lightweight composite GitHub Action** that reports which files changed between a base ref and `HEAD` — as a JSON array you can gate CI steps on.

- No Docker image, no Node runtime — pure `bash` + `git` + `jq` (preinstalled on GitHub-hosted Linux runners)
- Handles shallow clones: auto-fetches the base ref and deepens history until a merge base exists
- Regex filtering for monorepo-style path gating
- ~60 lines of shell you can read in one sitting

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
| `base-ref` | `origin/main` | Base commit, branch, or tag to compare against. |
| `pattern` | *(empty)* | ERE regex (`grep -E`). Only matching paths are included. Empty = all files. |

## Outputs

| Output | Description |
| :--- | :--- |
| `changed_files` | JSON-encoded string array of matching changed file paths. |
| `has_changes` | `"true"` if at least one file matched, otherwise `"false"`. |

## Notes

- Deleted files are excluded (`--diff-filter=ACMRT`): added, copied, modified, renamed, and type-changed files count.
- Run this action **after** `actions/checkout`. `fetch-depth: 0` (or `>= 50`) is recommended; the action still tries to fetch the base ref and deepen automatically for shallow clones.
- Requires `bash`, `git`, and `jq` — all preinstalled on `ubuntu-latest`.

## Security

Diff file paths can come from untrusted PRs. When consuming `changed_files` inside a `run:` step, always pass it through `env:` (as shown above) — never inline `${{ }}` interpolation into a script.

## Local development

```bash
bash scripts/smoke.sh
```

Spins up a throwaway git repository and exercises every `diff.sh` scenario (unfiltered diff, regex filter, no-changes, JSON validity).

## License

MIT
