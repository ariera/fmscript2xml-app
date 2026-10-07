#!/usr/bin/env bash
# Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Differential test (PLAN §9): converts every input.txt with both the Python
# and the Swift implementation and compares the output byte for byte, in
# continue-on-error and strict mode.
#
# Usage: tools/diff-against-python.sh [fixture-dir ...]
#   Defaults to Tests/Fixtures/public and $FMSCRIPT_PRIVATE_FIXTURES (if set).
# Env:   FMSCRIPT2XML_PYTHON_REPO  Python repo (default ~/dev/EMBO/fmscript2xml)
#        PYTHON                    interpreter (default: python3 in that repo)
#
# Outputs are written to a temporary directory; nothing is copied into the repo.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pyrepo="${FMSCRIPT2XML_PYTHON_REPO:-$HOME/dev/EMBO/fmscript2xml}"
dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  dirs=("$root/Tests/Fixtures/public")
  [ -n "${FMSCRIPT_PRIVATE_FIXTURES:-}" ] && dirs+=("$FMSCRIPT_PRIVATE_FIXTURES")
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift build -c release --package-path "$root" --product fmscript2xml >/dev/null
swiftcli="$(swift build -c release --package-path "$root" --show-bin-path)/fmscript2xml"

# List inputs (NUL-separated)
find "${dirs[@]}" -name input.txt -print0 | sort -z > "$work/inputs"
total=$(tr -cd '\0' < "$work/inputs" | wc -c | tr -d ' ')

# Python: one process converting every input in both modes
(cd "$pyrepo" && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$pyrepo/src" "${PYTHON:-python3}" - "$work" <<'PY'
import os, sys, hashlib
from fmscript2xml import Converter
work = sys.argv[1]
paths = open(os.path.join(work, "inputs"), "rb").read().split(b"\0")
c = Converter()
for p in filter(None, paths):
    p = p.decode()
    key = hashlib.sha1(p.encode()).hexdigest()
    text = open(p, encoding="utf-8").read()
    with open(os.path.join(work, key + ".py.continue"), "w", encoding="utf-8") as f:
        f.write(c.convert(text, stop_on_error=False))
    try:
        out = c.convert(text, stop_on_error=True)
    except Exception as e:
        out = "Error: %s\n" % e
    with open(os.path.join(work, key + ".py.strict"), "w", encoding="utf-8") as f:
        f.write(out)
PY
)

fail=0
while IFS= read -r -d '' p; do
  key=$(printf '%s' "$p" | shasum -a 1 | awk '{print $1}')
  "$swiftcli" "$p" --print --continue-on-error > "$work/$key.swift.continue" 2>/dev/null || true
  if ! "$swiftcli" "$p" --print > "$work/$key.swift.strict" 2> "$work/$key.err"; then
    cat "$work/$key.err" > "$work/$key.swift.strict"
  fi
  for mode in continue strict; do
    if ! cmp -s "$work/$key.py.$mode" "$work/$key.swift.$mode"; then
      fail=$((fail + 1))
      echo "DIFF ($mode): $p"
      diff "$work/$key.py.$mode" "$work/$key.swift.$mode" | head -20 | sed 's/^/    /' || true
    fi
  done
done < "$work/inputs"

echo "$total inputs, $fail differences"
[ "$fail" -eq 0 ]
