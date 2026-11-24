# ofac-sdn-mirror

A verbatim daily mirror of the U.S. Treasury OFAC **Specially Designated Nationals** list, `SDN.CSV`,
as published at `sanctionslistservice.ofac.treas.gov`. Public-domain U.S. government data; no changes.

Why it exists: OFAC's download hosts refuse requests from Cloudflare Workers (HTTP 525 / timeout), so
TunnelMind's Data API refreshes its sanctions index from this file instead:
`https://raw.githubusercontent.com/TunnelMind/ofac-sdn-mirror/main/SDN.CSV`

The refresh workflow force-pushes a single squashed commit whenever the upstream file changes, so the
repository holds one version and never grows. `SDN.CSV.sha256` is the checksum of the current file.
The authoritative source is always OFAC.

`SDN.CSV.meta.json` (since 2026-09-17) records the upstream `Last-Modified` as `published_at`, the
`ETag`, our `fetched_at` and the sha256 — the Data API reads it to report how old the list it is
screening against actually is (spec 090); freshness is judged on the publication time, never on the mirror's fetch time.

Refresh rule: when upstream sends identical bytes but a new `Last-Modified` or `ETag`, only
`SDN.CSV.meta.json` is republished — `SDN.CSV` and its sha256 are untouched and the commit message says
"bytes unchanged". A header missing from the response keeps its previous value in the meta file. Bad
responses are never published: a non-200 final status, an empty body, a body under the size floor, a
first line that is not CSV, or an HTML body is refused before any file changes. The meta file is written as
valid JSON (the etag is escaped).
