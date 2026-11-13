#!/bin/sh
# refresh.sh HEADERS BODY [REPO_DIR] — decide and write; the workflow owns git.
# Writes SDN.CSV, SDN.CSV.sha256, SDN.CSV.meta.json under REPO_DIR (default .)
# and prints one decision word as the LAST stdout line: bytes | unchanged.
set -eu
HEADERS=$1 BODY=$2 DIR=${3:-.}

# Spec 090 (TunnelMind data-api): the PUBLICATION time is the object's Last-Modified (the last
# response's headers, after the redirect); the consumer judges freshness on it, not on our
# fetch time. Written as a sidecar next to the file, also when the file itself is unchanged.
published=$(awk 'BEGIN{IGNORECASE=1} /^last-modified:/{v=$0} END{sub(/^[^:]*: */,"",v); gsub(/\r/,"",v); print v}' "$HEADERS")
etag=$(awk 'BEGIN{IGNORECASE=1} /^etag:/{v=$0} END{sub(/^[^:]*: */,"",v); gsub(/\r/,"",v); print v}' "$HEADERS")
rm -f "$HEADERS"
if cmp -s "$BODY" "$DIR/SDN.CSV" && [ -s "$DIR/SDN.CSV.meta.json" ]; then
  rm "$BODY"; echo unchanged; exit 0
fi
mv "$BODY" "$DIR/SDN.CSV"
# cd so the .sha256 holds "<hash>  SDN.CSV", not a path
(cd "$DIR" && sha256sum SDN.CSV > SDN.CSV.sha256)
printf '{"published_at":"%s","etag":"%s","fetched_at":"%s","sha256":"%s"}\n' \
  "$published" "$etag" "$(date -u +%FT%TZ)" "$(cut -c1-64 "$DIR/SDN.CSV.sha256")" > "$DIR/SDN.CSV.meta.json"
echo bytes
