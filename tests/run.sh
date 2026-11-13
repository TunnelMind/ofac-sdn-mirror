#!/bin/sh
# Offline tests for scripts/refresh.sh; every case runs in a mktemp dir, never the real repo files.
# Run from the repo root: sh tests/run.sh
FX=tests/fixtures
rc=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# case NAME BODYFIXTURE EXPECT_WORD EXPECT_CHANGED("yes"/"no" for CSV sha meta, e.g. "yes yes yes") [HEADERS [ETAG [LOGTEXT [METATEXT]]]]
# The starting meta matches new.headers, so "all same" means every header equals the previous value.
# LOGTEXT / METATEXT: substrings that must appear in the script output / the meta file.
# When meta is rewritten it must parse as JSON; with ETAG given, the parsed etag must equal it.
run_case() {
  name=$1 body=$2 word=$3 want=$4 hdr=${5:-new.headers} etag=${6-} logt=${7-} metat=${8-}
  d=$T/$name; mkdir -p "$d/repo" "$d/before"
  cp $FX/old.csv "$d/repo/SDN.CSV"
  (cd "$d/repo" && sha256sum SDN.CSV > SDN.CSV.sha256)
  printf '{"published_at":"Fri, 06 Nov 2026 14:00:00 GMT","etag":"\\"abc123\\"","fetched_at":"f","sha256":"%s"}\n' \
    "$(cut -c1-64 "$d/repo/SDN.CSV.sha256")" > "$d/repo/SDN.CSV.meta.json"
  cp "$d/repo"/SDN.CSV* "$d/before/"
  cp "$FX/$hdr" "$d/h"; cp "$FX/$body" "$d/b"
  out=$(sh scripts/refresh.sh "$d/h" "$d/b" "$d/repo" 2>&1)
  got=$(printf '%s\n' "$out" | tail -n1)
  changed=
  for f in SDN.CSV SDN.CSV.sha256 SDN.CSV.meta.json; do
    if cmp -s "$d/before/$f" "$d/repo/$f"; then changed="$changed no"; else changed="$changed yes"; fi
  done
  jsonok=yes
  case $changed in *yes) # meta (last file) was written
    python3 -m json.tool "$d/repo/SDN.CSV.meta.json" >/dev/null 2>&1 || jsonok=no
    if [ -n "$etag" ] && [ "$jsonok" = yes ]; then
      [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["etag"])' "$d/repo/SDN.CSV.meta.json")" = "$etag" ] || jsonok=no
    fi;; esac
  [ -z "$logt" ] || case $out in *"$logt"*) ;; *) jsonok=no;; esac
  [ -z "$metat" ] || grep -qF "$metat" "$d/repo/SDN.CSV.meta.json" || jsonok=no
  if [ "$got" = "$word" ] && [ "${changed# }" = "$want" ] && [ $jsonok = yes ]; then echo "PASS $name"
  else echo "FAIL $name (word=$got changed=${changed# } json=$jsonok)"; rc=1; fi
}

run_case "bytes changed" new.csv bytes "yes yes yes"
run_case "all same" old.csv unchanged "no no no"
run_case "ETag with quotes" new.csv bytes "yes yes yes" quoted-etag.headers '"81a3d1b64f269f171ec91f55c9bbe799"'

run_case "bytes same + Last-Modified changed" old.csv meta "no no yes" lm-changed.headers
run_case "bytes same + ETag changed" old.csv meta "no no yes" etag-changed.headers '"def456"'
run_case "missing Last-Modified" old.csv unchanged "no no no" no-lm.headers "" "kept previous published_at: header missing"
run_case "missing Last-Modified, ETag changed" old.csv meta "no no yes" no-lm-etag-changed.headers '"def456"' "kept previous published_at: header missing" "Fri, 06 Nov 2026 14:00:00 GMT"
run_case "missing ETag" old.csv unchanged "no no no" no-etag.headers "" "kept previous etag: header missing"
run_case "missing ETag, Last-Modified changed" old.csv meta "no no yes" no-etag-lm-changed.headers '"abc123"' "kept previous etag: header missing" "Sat, 07 Nov 2026 10:00:00 GMT"
# SC-004: the real 2026-11-09 republication; sha256 must stay the old.csv hash (76525c96…; the brief's 7f43332d… is the real SDN.CSV, not this fixture).
run_case "SC-004" old.csv meta "no no yes" sc004.headers "" "" "\"sha256\":\"$(sha256sum $FX/old.csv | cut -c1-8)"
# SC-004 on the real mirror files (copied, never touched): legacy invalid meta + new Last-Modified.
d=$T/sc004real; mkdir -p "$d/repo"; cp SDN.CSV SDN.CSV.sha256 SDN.CSV.meta.json "$d/repo/"
# legacy.headers matches the real meta (ETag included), so only Last-Modified differs.
cp SDN.CSV "$d/b"; sed "s/^Last-Modified:.*/Last-Modified: Mon, 09 Nov 2026 19:36:18 GMT\r/" $FX/legacy.headers > "$d/h"
w=$(sh scripts/refresh.sh "$d/h" "$d/b" "$d/repo" 2>&1 | tail -n1)
if [ "$w" = meta ] && cmp -s SDN.CSV "$d/repo/SDN.CSV" && cmp -s SDN.CSV.sha256 "$d/repo/SDN.CSV.sha256" \
  && python3 -m json.tool "$d/repo/SDN.CSV.meta.json" >/dev/null 2>&1 \
  && [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$d/repo/SDN.CSV.meta.json")" = 7f43332dae0d1b78ce44c31692d87a3c66e4075bcd97e36d3f18585572ff55b8 ]; then echo "PASS SC-004 real SDN.CSV"
else echo "FAIL SC-004 real SDN.CSV (word=$w)"; rc=1; fi

# Legacy invalid meta (unescaped quotes): the reader must see the same etag as the escaped form,
# and same bytes + existing meta must stay "unchanged" with nothing touched.
eval "$(sed -n '/^meta_get()/,/^}/p' scripts/refresh.sh)"
want='"81a3d1b64f269f171ec91f55c9bbe799"'
esc='{"published_at":"p","etag":"\"81a3d1b64f269f171ec91f55c9bbe799\"","fetched_at":"f","sha256":"s"}'
printf '%s\n' "$esc" > "$T/esc.json"
if [ "$(meta_get etag fetched_at $FX/legacy.meta.json)" = "$want" ] && [ "$(meta_get etag fetched_at "$T/esc.json")" = "$want" ] \
  && [ "$(meta_get published_at etag $FX/legacy.meta.json)" = "Fri, 06 Nov 2026 19:33:18 GMT" ]; then echo "PASS legacy reader"
else echo "FAIL legacy reader"; rc=1; fi
d=$T/legacy; mkdir -p "$d"; cp $FX/old.csv "$d/SDN.CSV"; (cd "$d" && sha256sum SDN.CSV > SDN.CSV.sha256)
cp $FX/legacy.meta.json "$d/SDN.CSV.meta.json"; cp -r "$d" "$T/legacy.before"
cp $FX/legacy.headers "$T/lh"; cp $FX/old.csv "$T/lb"
if [ "$(sh scripts/refresh.sh "$T/lh" "$T/lb" "$d" | tail -n1)" = unchanged ] && diff -r "$d" "$T/legacy.before" >/dev/null; then echo "PASS legacy invalid meta"
else echo "FAIL legacy invalid meta"; rc=1; fi
exit $rc
