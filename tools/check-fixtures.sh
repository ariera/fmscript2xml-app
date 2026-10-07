#!/usr/bin/env bash
# Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# D14 safeguard: production FileMaker scripts must never be committed.
#
# Usage:
#   tools/check-fixtures.sh --staged   # pre-commit: check files staged for commit
#   tools/check-fixtures.sh --tracked  # CI: check every tracked file
#
# Checks:
#   1. No file under Tests/Fixtures/ outside Tests/Fixtures/public/.
#   2. (local only) No staged/tracked file is byte-identical to a private
#      fixture input in $FMSCRIPT_PRIVATE_FIXTURES.
#   3. (local only) No staged/tracked file contains a term from a local,
#      untracked denylist ($FMSCRIPT_DENYLIST, default .git/info/fmscript-denylist),
#      one case-insensitive fixed string per line.
set -euo pipefail

mode="${1:---staged}"
cd "$(git rev-parse --show-toplevel)"

case "$mode" in
  --staged)  files=$(git diff --cached --name-only --diff-filter=ACMR) ;;
  --tracked) files=$(git ls-files) ;;
  *) echo "usage: $0 [--staged|--tracked]" >&2; exit 2 ;;
esac

status=0

# 1. Location check
bad=$(printf '%s\n' "$files" | grep -E '^Tests/Fixtures/' | grep -vE '^Tests/Fixtures/public/' || true)
if [ -n "$bad" ]; then
  echo "error: files under Tests/Fixtures/ must live in Tests/Fixtures/public/ (D14):" >&2
  printf '  %s\n' $bad >&2
  status=1
fi

# Content of a file as it will be committed (index for --staged, worktree otherwise).
content() {
  if [ "$mode" = "--staged" ]; then git show ":$1" 2>/dev/null; else cat "$1" 2>/dev/null; fi
}

# 2. Byte-identical copies of private fixtures
if [ -n "${FMSCRIPT_PRIVATE_FIXTURES:-}" ] && [ -d "$FMSCRIPT_PRIVATE_FIXTURES" ] && [ -n "$files" ]; then
  private_hashes=$(find "$FMSCRIPT_PRIVATE_FIXTURES" -type f \( -name 'input.txt' -o -name 'expected.xml' \) -print0 \
    | xargs -0 shasum -a 1 | awk '{print $1}' | sort -u)
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    h=$(content "$f" | shasum -a 1 | awk '{print $1}')
    if printf '%s\n' "$private_hashes" | grep -qx "$h"; then
      echo "error: $f is identical to a private fixture in \$FMSCRIPT_PRIVATE_FIXTURES (D14)" >&2
      status=1
    fi
  done <<< "$files"
fi

# 3. Local denylist of production names
denylist="${FMSCRIPT_DENYLIST:-.git/info/fmscript-denylist}"
if [ -f "$denylist" ] && [ -n "$files" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # PLAN.md names a few production identifiers on purpose, as scrubbing examples.
    [ "$f" = "PLAN.md" ] && continue
    if hits=$(content "$f" | grep -n -i -F -f <(grep -v '^\s*$' "$denylist" | grep -v '^#') 2>/dev/null); then
      echo "error: $f contains denylisted production names (D14):" >&2
      printf '%s\n' "$hits" | head -5 | sed 's/^/  /' >&2
      status=1
    fi
  done <<< "$files"
fi

exit $status
