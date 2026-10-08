#!/usr/bin/env bash
# Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Generates the Xcode project from App/project.yml and builds the app
# (ad-hoc signed). Usage: tools/build-app.sh [Debug|Release] [--open]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-Debug}"
xcodegen generate --spec "$root/App/project.yml" --quiet
xcodebuild -project "$root/App/FMScriptPaste.xcodeproj" -scheme FMScriptPaste \
  -configuration "$config" -derivedDataPath "$root/build/DerivedData" build -quiet
app="$root/build/DerivedData/Build/Products/$config/fmscript2xml.app"
echo "Built: $app"
[ "${2:-}" = "--open" ] && open "$app"
exit 0
