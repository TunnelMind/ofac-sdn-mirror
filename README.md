# ofac-sdn-mirror

A verbatim daily mirror of the U.S. Treasury OFAC **Specially Designated Nationals** list, `SDN.CSV`,
as published at `sanctionslistservice.ofac.treas.gov`. Public-domain U.S. government data; no changes.

Why it exists: OFAC's download hosts refuse requests from Cloudflare Workers (HTTP 525 / timeout), so
TunnelMind's Data API refreshes its sanctions index from this file instead:
`https://raw.githubusercontent.com/TunnelMind/ofac-sdn-mirror/main/SDN.CSV`

The refresh workflow force-pushes a single squashed commit whenever the upstream file changes, so the
repository holds one version and never grows. `SDN.CSV.sha256` is the checksum of the current file.
The authoritative source is always OFAC.
