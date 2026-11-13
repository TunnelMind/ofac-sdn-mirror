#!/bin/sh
# Offline tests for scripts/refresh.sh; every case runs in a mktemp dir, never the real repo files.
# Run from the repo root: sh tests/run.sh
FX=tests/fixtures
rc=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# case NAME BODYFIXTURE EXPECT_WORD EXPECT_CHANGED("yes"/"no" for CSV sha meta, e.g. "yes yes yes")
run_case() {
  name=$1 body=$2 word=$3 want=$4
  d=$T/$name; mkdir -p "$d/repo" "$d/before"
  cp $FX/old.csv "$d/repo/SDN.CSV"
  (cd "$d/repo" && sha256sum SDN.CSV > SDN.CSV.sha256)
  echo '{"old":"meta"}' > "$d/repo/SDN.CSV.meta.json"
  cp "$d/repo"/SDN.CSV* "$d/before/"
  cp $FX/new.headers "$d/h"; cp "$FX/$body" "$d/b"
  out=$(sh scripts/refresh.sh "$d/h" "$d/b" "$d/repo" 2>&1)
  got=$(printf '%s\n' "$out" | tail -n1)
  changed=
  for f in SDN.CSV SDN.CSV.sha256 SDN.CSV.meta.json; do
    if cmp -s "$d/before/$f" "$d/repo/$f"; then changed="$changed no"; else changed="$changed yes"; fi
  done
  if [ "$got" = "$word" ] && [ "${changed# }" = "$want" ]; then echo "PASS $name"
  else echo "FAIL $name (word=$got changed=${changed# })"; rc=1; fi
}

run_case "bytes changed" new.csv bytes "yes yes yes"
run_case "all same" old.csv unchanged "no no no"
exit $rc
