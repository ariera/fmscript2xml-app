#!/usr/bin/env bash
# Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Creates a synthetic public fixture from an input file, with expected.xml
# produced by a reference implementation (continue-on-error mode).
#
#   tools/new-fixture.sh <Name> <input.txt> [--reference python|swift]
#
# Inputs must be synthetic: no production table, field, layout or script
# names (D14). Fixtures produced this way are regression fixtures and are
# compared byte for byte; see Tests/Fixtures/public/README.md.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
name="$1"; input="$2"; ref="python"
[ "${3:-}" = "--reference" ] && ref="$4"
dir="$root/Tests/Fixtures/public/$name"
mkdir -p "$dir"
cp "$input" "$dir/input.txt"
case "$ref" in
  python)
    pyrepo="${FMSCRIPT2XML_PYTHON_REPO:-$HOME/dev/EMBO/fmscript2xml}"
    (cd "$pyrepo" && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$pyrepo/src" "${PYTHON:-python3}" -c '
import sys
from fmscript2xml import Converter
sys.stdout.write(Converter().convert(open(sys.argv[1], encoding="utf-8").read(), stop_on_error=False))
' "$dir/input.txt") > "$dir/expected.xml" ;;
  swift)
    swift run --package-path "$root" -c release fmscript2xml "$dir/input.txt" --print --continue-on-error > "$dir/expected.xml" ;;
  *) echo "unknown reference: $ref" >&2; exit 2 ;;
esac
echo "Created $dir"
