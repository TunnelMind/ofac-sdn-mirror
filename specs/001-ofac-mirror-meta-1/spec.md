# Feature: ofac-mirror-meta-1 — the mirror's metadata follows OFAC's publish date even when the bytes are the same

Repo: `ofac-sdn-mirror` (PUBLIC). One PR back to the owner. No merge, no workflow run, no push to main, no force-push, no secret.

## Intent

When OFAC re-publishes `SDN.CSV` with a new `Last-Modified` or `ETag` but byte-identical content, the mirror must still update `SDN.CSV.meta.json` so the Data API (tunnelmind-spec spec 090) reports the true publish date. The refresh logic moves into a tested shell script that also refuses to publish bad responses and always writes valid JSON.

Owner, 2026-11-13: *"ofac-sdn-mirror: have the refresh workflow also update the metadata when OFAC's published date or tag changes, even if the bytes are the same."*

Measured 2026-11-13: *"OFAC served Last-Modified "Mon, 09 Nov 2026 19:36:18 GMT" with a new ETag while the file was byte-identical (sha256 7f43332d...) to the mirror's copy, whose meta still says published_at "Fri, 06 Nov 2026 19:33:18 GMT"."*

## Current behaviour (read from `.github/workflows/refresh.yml`, step `fetch`)

- `curl -sSL -m 120 -D headers.txt … -o SDN.CSV.new` — no `-f`, so a non-200 final response is **not** rejected by curl.
- Sanity line: `test "$(stat -c %s SDN.CSV.new)" -gt 1000000 && head -c 200 SDN.CSV.new | grep -q '"'`. Under GitHub's `bash -e`, a failure of the first command of an `&&` list does not abort the step, so **the 1 MB size floor is not enforced today**; only "a `"` appears in the first 200 bytes" is. An HTML error page containing a quote passes.
- `published` / `etag` are taken from the last `Last-Modified:` / `ETag:` line in `headers.txt`; a missing header yields an empty string that is written as-is.
- `cmp -s SDN.CSV.new SDN.CSV && [ -s SDN.CSV.meta.json ]` → prints `unchanged`, exits 0. **Meta is never refreshed on identical bytes** (the bug).
- Otherwise: replaces `SDN.CSV`, rewrites `SDN.CSV.sha256` (`sha256sum` format), writes meta with `printf '{"published_at":"%s","etag":"%s",…}'` — the ETag's own quotes are not escaped, so the committed `SDN.CSV.meta.json` is **invalid JSON** today (`python3 -m json.tool SDN.CSV.meta.json` → `Expecting ',' delimiter: line 1 column 58`). Then an orphan commit `SDN.CSV <date> <sha12>` is force-pushed to main.
- `SDN.CSV` has no header row; real line 1 starts `36,"AEROCARIBBEAN AIRLINES",…` and lines end `\r\n`.

## User Scenarios

### US1 — publish date follows OFAC on identical bytes (P1)
Given the mirror holds `SDN.CSV` with meta `published_at = Fri, 06 Nov 2026 19:33:18 GMT`, when OFAC serves byte-identical content with `Last-Modified: Mon, 09 Nov 2026 19:36:18 GMT` (and/or a new ETag), then only `SDN.CSV.meta.json` changes (`published_at`, `etag`, `fetched_at` updated; `sha256` unchanged), `SDN.CSV` and `SDN.CSV.sha256` are untouched, and the workflow publishes one squashed orphan commit whose message says the bytes did not change.

### US2 — nothing changed (P1)
Given bytes, Last-Modified and ETag all match the meta, then the run prints `unchanged`, no file changes, no commit.

### US3 — bytes changed (P1)
Given new bytes, then `SDN.CSV`, `SDN.CSV.sha256`, `SDN.CSV.meta.json` are rewritten exactly as today and the commit message keeps today's form `SDN.CSV <YYYY-MM-DD> <sha12>`.

### US4 — bad upstream responses are never published (P1)
Given a non-200 final status, an empty body, an HTML body, or a body under the size floor / whose first line does not look like an SDN row, then the script exits non-zero, no repo file changes, and nothing is committed.

### US5 — missing headers do not blank known values (P2)
Given a response without `Last-Modified` (or without `ETag`), then that field keeps its previous value from meta and the log says so; the other field still updates normally.

### US6 — valid JSON (P1)
Given an ETag like `"81a3d1b64f269f171ec91f55c9bbe799"` (with quotes, or containing a backslash), then the written meta parses with `python3 -m json.tool`, and the field names are exactly `published_at`, `etag`, `fetched_at`, `sha256`.

## Functional Requirements

- **FR-001** The fetch-and-decide logic lives in `scripts/refresh.sh` (POSIX sh, no new dependency; coreutils/awk/sed/grep only). The workflow downloads, calls the script, and owns all git/push steps. The script never runs git.
- **FR-002** Inputs: a headers file (curl `-D` output, possibly several responses after redirects), the downloaded body, and the repo directory (defaults to `.`). Output: on stdout, exactly one decision word on the last line — `bytes`, `meta` or `unchanged` — and non-zero exit for rejected input.
- **FR-003** Only the **last** response block in the headers file counts (status line, `Last-Modified`, `ETag`), case-insensitive header names, `\r` stripped.
- **FR-004** Reject (exit non-zero, no files changed) when: final status is not 200; body is empty; body is smaller than the size floor (`MIN_BYTES`, default `1000000`; env override exists so tests can use small fixtures — the workflow does not set it); first line does not match an SDN row (`^[0-9][0-9]*,"`); body looks like HTML (`<` as first non-space char, or `<html`/`<!doctype` case-insensitive in the first 1 KB).
- **FR-005** Bytes differ (or no meta yet): replace `SDN.CSV`, write `SDN.CSV.sha256` in `sha256sum` format, write meta; decision `bytes`.
- **FR-006** Bytes same and meta exists: if upstream `Last-Modified` or `ETag` (after FR-007 fallback) differs from meta, rewrite meta only (`sha256` copied from the existing meta/`SDN.CSV.sha256`, `fetched_at` = now); decision `meta`. Else decision `unchanged`, no file touched.
- **FR-007** Missing `Last-Modified` or `ETag` in the response: use the value already in meta for that field and log `kept previous <field>: header missing`. If both are missing and bytes are the same → `unchanged`.
- **FR-008** Meta writer escapes `\` and `"` in every string value (JSON); single line + trailing newline, same key order as today.
- **FR-009** Meta reader extracts the previous `published_at` and `etag` from both the new (valid, escaped) form and the legacy invalid form currently committed (`"etag":""81a…""`), so the first run after merge compares correctly and rewrites valid JSON.
- **FR-010** Workflow commit message: byte path unchanged (`SDN.CSV $(date -u +%F) <sha12>`); meta path `SDN.CSV.meta.json $(date -u +%F) <sha12> (bytes unchanged)`; both via the existing orphan + `git push --force origin main` steps. `unchanged` → step exits 0 without git.
- **FR-011** The step aborts on any rejection (the size floor must actually be enforced; no `a && b` sanity line whose first half is ignored by `bash -e`).
- **FR-012** `tests/run.sh` (plain sh) runs the script against fixtures in a temp copy (never the real repo files, never the network) for: bytes changed; bytes same + Last-Modified changed; bytes same + ETag changed; all same; missing Last-Modified; missing ETag; non-200 final (incl. a 302→404 chain); empty body; HTML body; ETag with quotes; legacy invalid meta. Each asserts which of `SDN.CSV`, `SDN.CSV.sha256`, `SDN.CSV.meta.json` changed, the decision word / exit status, and that the meta parses (`python3 -m json.tool`). Exits non-zero on any failure, prints `PASS`/`FAIL` per case.
- **FR-013** New workflow `.github/workflows/test.yml`: `on: pull_request` (and `push` to non-main branches not required), `permissions: contents: read`, one job running `sh tests/run.sh`; no secrets, no push.
- **FR-014** README gains one paragraph on the meta-only rule.

## Success Criteria

- **SC-001** `sh tests/run.sh` exits 0 and prints PASS for all ≥11 cases in FR-012.
- **SC-002** `grep -n 'git ' scripts/refresh.sh` returns nothing (script never pushes/commits).
- **SC-003** `grep -nE 'secrets\.|contents: write|push' .github/workflows/test.yml` returns nothing.
- **SC-004** Running the script on a temp copy of the repo with the real `SDN.CSV` as body and a header file carrying `Last-Modified: Mon, 09 Nov 2026 19:36:18 GMT` prints `meta`, leaves `SDN.CSV`/`SDN.CSV.sha256` byte-identical, and the new meta passes `python3 -m json.tool` with `sha256` = `7f43332dae0d1b78ce44c31692d87a3c66e4075bcd97e36d3f18585572ff55b8` (a case in tests/run.sh may use a copy of the real file; it must not be committed twice).
- **SC-005** `refresh.yml` byte path produces the same three files and commit message format as today (diff review by the reviewer).

## Edge Cases

- Redirect chains: several header blocks in `headers.txt`; only the final block counts.
- Header name casing (`etag`, `ETag`, `Last-modified`) and CRLF line ends.
- Weak ETags (`W/"…"`) — stored verbatim, escaped.
- No meta file yet → byte path even if `SDN.CSV` matches (today's behaviour).
- Legacy invalid meta in the repo now (FR-009).
- Both headers missing and bytes same → `unchanged` (nothing new to record).
- Body with a UTF-8 BOM or trailing `\x1a` (the real file ends `\r\n\x1a`) — must still pass; only line 1 is checked.

## Assumptions

- The Data API reads `published_at` (and possibly `etag`) by field name; switching the ETag to properly escaped JSON (`"etag":"\"81a…\""`) keeps those names. If the Data API currently parses the invalid file with a regex rather than `JSON.parse`, the escaped form may change what it extracts — the owner should confirm (see owner task in tasks.md). This does not change what gets built here.
- `python3` exists on `ubuntu-latest` and on BEAST; used only by tests, not by the script.
- The workflow run itself is the owner's; the crew never triggers it.

## Out of Scope

- Changes to the Data API / tunnelmind-spec spec 090.
- Keeping history (single-version orphan design stays).
- Running the workflow, pushing main, merging.
