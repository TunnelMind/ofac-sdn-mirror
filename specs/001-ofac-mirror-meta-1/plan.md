# Plan: ofac-mirror-meta-1

## Constitution check

No `.specify/memory/constitution.md` and no `.specify/templates/` in this repo → no ADR rule, no extra gates beyond GATE F. Owner rules applied: no merge, no push to main, no workflow run, no secrets; every task keeps `sh tests/run.sh` green.

## Where the change goes

| Path | Change |
|------|--------|
| `scripts/refresh.sh` (new) | All decide/validate/write logic now inline in `.github/workflows/refresh.yml` step `fetch` |
| `.github/workflows/refresh.yml` | `fetch` step: curl (unchanged URL/UA/timeout) → `sh scripts/refresh.sh headers.txt SDN.CSV.new` → branch on decision for commit message → existing orphan commit + force-push |
| `tests/run.sh` (new) | Fixture-driven test runner, plain sh, temp dirs via `mktemp -d` |
| `tests/fixtures/` (new) | Header files (`*.headers`, CRLF) and tiny CSV bodies (a few SDN-shaped lines), an HTML page, an empty file, a legacy meta.json |
| `.github/workflows/test.yml` (new) | `pull_request` job, `contents: read`, runs `sh tests/run.sh` |
| `README.md` | One paragraph on the meta-only rule |

## Approach

- Script interface: `scripts/refresh.sh HEADERS BODY [REPO_DIR]`. Reads the final header block (`awk` resets on each `^HTTP/` line), validates (FR-004), compares with `cmp -s`, reads previous meta with `sed` that tolerates both legacy and escaped ETag forms (FR-009), writes meta via a small `json_esc` shell function (`sed 's/\\/\\\\/g; s/"/\\"/g'`) (FR-008). On success it moves/deletes `BODY` as today and prints the decision word last. `MIN_BYTES` env, default 1000000 — the calibration knob for tests.
- Workflow keeps the push: `decision=$(sh scripts/refresh.sh headers.txt SDN.CSV.new | tail -n1)`; `unchanged` → exit 0; `bytes`/`meta` → message per FR-010 → existing `git checkout --orphan fresh … git push --force origin main`. `headers.txt` removed after the script.
- `fetched_at` via `date -u +%FT%TZ` as today; tests don't assert its value, only that it changed on write paths and not on `unchanged`.

## Risks

- **Orphaned PR branch**: the daily job replaces main with a fresh orphan commit whenever it publishes; a PR branch cut today has no common ancestor with a later main. Rebase: `git fetch origin && git rebase --onto origin/main <old-main-sha> <branch>` (old-main-sha = `a5a2303` today, the branch's base), then `git push --force-with-lease` to the PR branch only (owner/coordinator step, never main). The PR's diff touches only `scripts/`, `tests/`, `.github/workflows/`, `README.md`, so the rebase is conflict-free unless README changed upstream.
- **The ETag escaping changes the on-disk bytes of `etag`** — consumer impact noted in spec Assumptions; owner check.
- **First publish after merge**: the committed meta is legacy-invalid and OFAC already published 2026-11-09 → the first run will take the `meta` path and fix both the date and the JSON. Expected, not a bug.
- `bash -e` vs `sh`: the script uses `set -eu` and explicit `|| exit` checks — no `a && b` sanity lines.

## Verify

`sh tests/run.sh` — must exit 0 at the end of every task.
