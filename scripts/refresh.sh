#!/bin/sh
# refresh.sh HEADERS BODY [REPO_DIR] — decide and write; the workflow owns git.
# Writes SDN.CSV, SDN.CSV.sha256, SDN.CSV.meta.json under REPO_DIR (default .)
# and prints one decision word as the LAST stdout line: bytes | meta | unchanged.
set -eu
HEADERS=$1 BODY=$2 DIR=${3:-.}

# Escape \ and " so header values (ETags are quoted) stay valid JSON strings.
json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
# meta_get KEY NEXTKEY FILE — previous string value of KEY from the one-line meta. Accepts the
# escaped form and the legacy invalid one (unescaped inner quotes); anchoring on the next key
# makes both parse. Unescapes \" and \\.
meta_get() {
  sed -n "s/.*\"$1\":\"\(.*\)\",\"$2\":.*/\1/p" "$3" | sed 's/\\\(["\\]\)/\1/g'
}

# Spec 090 (TunnelMind data-api): the PUBLICATION time is the object's Last-Modified (the last
# response's headers, after the redirect); the consumer judges freshness on it, not on our
# fetch time. Written as a sidecar next to the file, also when the file itself is unchanged.
published=$(awk 'BEGIN{IGNORECASE=1} /^last-modified:/{v=$0} END{sub(/^[^:]*: */,"",v); gsub(/\r/,"",v); print v}' "$HEADERS")
etag=$(awk 'BEGIN{IGNORECASE=1} /^etag:/{v=$0} END{sub(/^[^:]*: */,"",v); gsub(/\r/,"",v); print v}' "$HEADERS")
rm -f "$HEADERS"
if cmp -s "$BODY" "$DIR/SDN.CSV" && [ -s "$DIR/SDN.CSV.meta.json" ]; then
  rm "$BODY"
  # Same bytes: a republication that only moves Last-Modified/ETag rewrites the meta alone.
  # A header missing from the response keeps its previous value.
  M=$DIR/SDN.CSV.meta.json; moved=
  oldp=$(meta_get published_at etag "$M"); olde=$(meta_get etag fetched_at "$M")
  if [ -z "$published" ]; then echo "kept previous published_at: header missing" >&2; published=$oldp
  elif [ "$published" != "$oldp" ]; then moved=1; fi
  if [ -z "$etag" ]; then echo "kept previous etag: header missing" >&2; etag=$olde
  elif [ "$etag" != "$olde" ]; then moved=1; fi
  [ -n "$moved" ] || { echo unchanged; exit 0; }
  # Never write an empty hash: if the .sha256 is missing, hash the (identical) CSV itself.
  sha=$(cut -c1-64 "$DIR/SDN.CSV.sha256" 2>/dev/null || true)
  [ -n "$sha" ] || sha=$(sha256sum "$DIR/SDN.CSV" | cut -c1-64)
  printf '{"published_at":"%s","etag":"%s","fetched_at":"%s","sha256":"%s"}\n' \
    "$(json_esc "$published")" "$(json_esc "$etag")" "$(date -u +%FT%TZ)" "$sha" > "$M"
  echo meta; exit 0
fi
mv "$BODY" "$DIR/SDN.CSV"
# cd so the .sha256 holds "<hash>  SDN.CSV", not a path
(cd "$DIR" && sha256sum SDN.CSV > SDN.CSV.sha256)
printf '{"published_at":"%s","etag":"%s","fetched_at":"%s","sha256":"%s"}\n' \
  "$(json_esc "$published")" "$(json_esc "$etag")" "$(date -u +%FT%TZ)" "$(cut -c1-64 "$DIR/SDN.CSV.sha256")" > "$DIR/SDN.CSV.meta.json"
echo bytes
