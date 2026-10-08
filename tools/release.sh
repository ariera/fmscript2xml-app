#!/usr/bin/env bash
# Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds, signs, notarises and publishes a release (PLAN §10, Phase 6).
# Runs locally on the maintainer's Mac: signing secrets never go to GitHub.
#
#   tools/release.sh <version> [--ad-hoc | --dry-run]
#
# <version> is x.y or x.y.z. Every 0.x release is a beta: 0.1 is published
# as "fmscript2xml 0.1 beta" (tag v0.1.0). The GitHub pre-release flag is
# not used, because releases/latest (download links and the Sparkle feed)
# skips pre-releases.
#
# Modes:
#   (default)  Developer ID signed and notarised. Needs the setup below.
#   --ad-hoc   Ad-hoc signed, not notarised, published. No Apple Developer
#              account needed, but macOS blocks the first launch: users
#              click "Open Anyway" in System Settings → Privacy & Security
#              once (the release notes explain it).
#   --dry-run  Ad-hoc build and DMG in build/release/, nothing published.
#
# One-time setup on the release Mac:
#   1. "Developer ID Application" certificate for EMBO's team in the login
#      keychain (issued by EMBO's Account Holder/Admin).
#   2. Notarisation credentials:
#        xcrun notarytool store-credentials fmscript2xml-notary \
#          --apple-id <id> --team-id <TEAM_ID> --password <app-specific password>
#   3. Sparkle EdDSA key: run Sparkle's generate_keys once (it stores the
#      private key in the keychain and prints the public key), and put the
#      public key in SPARKLE_PUBLIC_ED_KEY in App/project.yml.
# Steps 1 and 2 aren't needed for --ad-hoc. Without step 3 an --ad-hoc
# release has no update feed (the app won't offer updates).
#
# Environment:
#   FMSP_TEAM_ID          Apple Developer team ID (required unless --dry-run)
#   FMSP_NOTARY_PROFILE   notarytool keychain profile (default: fmscript2xml-notary)
set -euo pipefail

usage() { echo "usage: $0 <version, e.g. 0.1 or 1.2.3> [--ad-hoc | --dry-run]" >&2; exit 2; }
[ $# -ge 1 ] || usage
version="$1"
mode="signed"
case "${2:-}" in
  "") ;;
  --ad-hoc) mode="adhoc" ;;
  --dry-run) mode="dry" ;;
  *) usage ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] && version="$version.0"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must look like 0.1 or 1.2.3" >&2; exit 2; }
IFS=. read -r major minor patch <<< "$version"
# What people see: every 0.x is a beta
if [ "$major" = "0" ]; then
  if [ "$patch" = "0" ]; then display="0.$minor beta"; else display="0.$minor.$patch beta"; fi
else
  display="$version"
fi
dry=0
[ "$mode" = "dry" ] && dry=1

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/release"
app_name="fmscript2xml"
repo="ariera/fmscript2xml-app"
tag="v$version"
build_number="$(git -C "$root" rev-list --count HEAD)"
team="${FMSP_TEAM_ID:-}"
notary_profile="${FMSP_NOTARY_PROFILE:-fmscript2xml-notary}"
identity="Developer ID Application"

step() { printf '\n==> %s\n' "$*"; }

# --- Checks -----------------------------------------------------------------
step "Checks: $app_name $display ($mode)"
cd "$root"
has_sparkle_key=0
grep -Eq 'SPARKLE_PUBLIC_ED_KEY: "[^"]+"' App/project.yml && has_sparkle_key=1
if [ $dry -eq 0 ]; then
  [ -z "$(git status --porcelain)" ] || { echo "error: the working tree has changes" >&2; exit 1; }
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "error: release from main" >&2; exit 1; }
  ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "error: tag $tag exists" >&2; exit 1; }
fi
if [ "$mode" = "signed" ]; then
  [ -n "$team" ] || { echo "error: set FMSP_TEAM_ID" >&2; exit 1; }
  security find-identity -v -p codesigning | grep -q "$identity" \
    || { echo "error: no '$identity' certificate in the keychain (use --ad-hoc to release without one)" >&2; exit 1; }
  [ $has_sparkle_key -eq 1 ] \
    || { echo "error: SPARKLE_PUBLIC_ED_KEY is empty in App/project.yml (updates would be off)" >&2; exit 1; }
fi
if [ "$mode" = "adhoc" ] && [ $has_sparkle_key -eq 0 ]; then
  echo "warning: SPARKLE_PUBLIC_ED_KEY is empty: this release won't offer updates" >&2
fi
tools/check-fixtures.sh --tracked
swift test --quiet

# --- Build ------------------------------------------------------------------
step "Archive $app_name $version ($build_number)"
rm -rf "$out"
mkdir -p "$out"
xcodegen generate --spec App/project.yml --quiet
sign_settings=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" "DEVELOPMENT_TEAM=$team" "OTHER_CODE_SIGN_FLAGS=--timestamp")
# Ad-hoc builds have no Team ID. With the hardened runtime on, library
# validation then refuses Sparkle.framework (signed by Sparkle's team) and
# the app is killed at launch, so ad-hoc builds run without it.
[ "$mode" != "signed" ] && sign_settings=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=-" DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
xcodebuild archive -quiet \
  -project App/FMScriptPaste.xcodeproj -scheme FMScriptPaste -configuration Release \
  -archivePath "$out/FMScriptPaste.xcarchive" -derivedDataPath "$out/DerivedData" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" "${sign_settings[@]}"

step "Export"
if [ "$mode" != "signed" ]; then
  mkdir -p "$out/export"
  ditto "$out/FMScriptPaste.xcarchive/Products/Applications/$app_name.app" "$out/export/$app_name.app"
else
  cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$identity</string>
  <key>teamID</key><string>$team</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -quiet -archivePath "$out/FMScriptPaste.xcarchive" \
    -exportOptionsPlist "$out/ExportOptions.plist" -exportPath "$out/export"
fi
app="$out/export/$app_name.app"
codesign --verify --deep --strict "$app"

# Smoke test: the app must launch (frameworks load) and quit cleanly
step "Smoke test"
"$app/Contents/MacOS/$app_name" -FMSPSmokeTest YES >"$out/smoke.log" 2>&1 &
smoke_pid=$!
for _ in $(seq 1 30); do kill -0 "$smoke_pid" 2>/dev/null || break; sleep 1; done
if kill -0 "$smoke_pid" 2>/dev/null; then
  kill "$smoke_pid"; echo "error: the app didn't quit after the smoke test" >&2; exit 1
fi
wait "$smoke_pid" || { echo "error: the app failed to launch:" >&2; cat "$out/smoke.log" >&2; exit 1; }
grep -q "smoke test: ok" "$out/smoke.log" || { echo "error: no smoke test confirmation" >&2; cat "$out/smoke.log" >&2; exit 1; }
echo "launches and quits cleanly"
plist="$app/Contents/Info.plist"
echo "Built $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist"))"

# --- DMG --------------------------------------------------------------------
step "DMG"
dmg="$out/fmscript2xml-${display// /-}.dmg"
staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "$app_name $display" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
echo "$dmg"

if [ $dry -eq 1 ]; then
  step "Dry run done: $dmg (ad-hoc signed, not notarised, not published)"
  exit 0
fi

if [ "$mode" = "signed" ]; then
  codesign --sign "$identity" --timestamp "$dmg"

  # --- Notarise --------------------------------------------------------------
  step "Notarise"
  xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature -vv "$dmg"
fi

# --- Appcast -------------------------------------------------------------------
assets=("$dmg")
if [ $has_sparkle_key -eq 1 ]; then
  step "Sparkle appcast"
  generate_appcast="$(find "$out/DerivedData/SourcePackages/artifacts" -path '*Sparkle/bin/generate_appcast' -type f | head -1)"
  [ -x "$generate_appcast" ] || { echo "error: generate_appcast not found" >&2; exit 1; }
  mkdir -p "$out/updates"
  cp "$dmg" "$out/updates/"
  "$generate_appcast" --download-url-prefix "https://github.com/$repo/releases/download/$tag/" \
    --link "https://github.com/$repo" -o "$out/appcast.xml" "$out/updates"
  assets+=("$out/appcast.xml")
fi

# --- Release notes ------------------------------------------------------------
notes="$out/notes.md"
{
  [ "$major" = "0" ] && printf '**Beta.** %s is in beta for all 0.x versions.\n\n' "$app_name"
  if [ "$mode" = "adhoc" ]; then
    cat <<'NOTES'
### Installing

This build isn't notarised by Apple, so macOS blocks it the first time:

1. Open the DMG and drag **fmscript2xml** to Applications.
2. Open it. macOS says it can't verify the developer. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down, click
   **Open Anyway** next to "fmscript2xml was blocked", and confirm.

You only do this once. Alternatively, in Terminal:
`xattr -dr com.apple.quarantine "/Applications/fmscript2xml.app"`

NOTES
  fi
  printf 'Requires macOS 14 or later.\n'
} > "$notes"

# --- Publish -----------------------------------------------------------------
step "GitHub Release $tag: $app_name $display"
git tag -a "$tag" -m "$app_name $display"
git push origin "$tag"
gh release create "$tag" "${assets[@]}" --repo "$repo" \
  --title "$app_name $display" --notes-file "$notes" --generate-notes
step "Released $tag"
