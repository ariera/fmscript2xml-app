#!/usr/bin/env bash
# Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds, signs, notarises and publishes a release (PLAN §10, Phase 6).
# Runs locally on the maintainer's Mac: signing secrets never go to GitHub.
#
#   tools/release.sh <version> [--dry-run]
#
# --dry-run builds an ad-hoc signed app and DMG in build/release/ and stops
# (no Developer ID, notarisation, appcast or upload). Use it to check the
# pipeline on any Mac.
#
# One-time setup on the release Mac:
#   1. "Developer ID Application" certificate for EMBO's team in the login
#      keychain (issued by EMBO's Account Holder/Admin).
#   2. Notarisation credentials:
#        xcrun notarytool store-credentials fmscriptpaste-notary \
#          --apple-id <id> --team-id <TEAM_ID> --password <app-specific password>
#   3. Sparkle EdDSA key: run Sparkle's generate_keys once (it stores the
#      private key in the keychain and prints the public key), and put the
#      public key in SPARKLE_PUBLIC_ED_KEY in App/project.yml.
#
# Environment:
#   FMSP_TEAM_ID          Apple Developer team ID (required unless --dry-run)
#   FMSP_NOTARY_PROFILE   notarytool keychain profile (default: fmscriptpaste-notary)
set -euo pipefail

usage() { echo "usage: $0 <version, e.g. 1.0.0> [--dry-run]" >&2; exit 2; }
[ $# -ge 1 ] || usage
version="$1"
dry=0
[ "${2:-}" = "--dry-run" ] && dry=1
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must look like 1.2.3" >&2; exit 2; }

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/release"
app_name="FM Script Paste"
repo="ariera/fmscript2xml-app"
tag="v$version"
build_number="$(git -C "$root" rev-list --count HEAD)"
team="${FMSP_TEAM_ID:-}"
notary_profile="${FMSP_NOTARY_PROFILE:-fmscriptpaste-notary}"
identity="Developer ID Application"

step() { printf '\n==> %s\n' "$*"; }

# --- Checks -----------------------------------------------------------------
step "Checks"
cd "$root"
if [ $dry -eq 0 ]; then
  [ -n "$team" ] || { echo "error: set FMSP_TEAM_ID" >&2; exit 1; }
  [ -z "$(git status --porcelain)" ] || { echo "error: the working tree has changes" >&2; exit 1; }
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "error: release from main" >&2; exit 1; }
  ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "error: tag $tag exists" >&2; exit 1; }
  security find-identity -v -p codesigning | grep -q "$identity" \
    || { echo "error: no '$identity' certificate in the keychain" >&2; exit 1; }
  grep -Eq 'SPARKLE_PUBLIC_ED_KEY: "[^"]+"' App/project.yml \
    || { echo "error: SPARKLE_PUBLIC_ED_KEY is empty in App/project.yml (updates would be off)" >&2; exit 1; }
fi
tools/check-fixtures.sh --tracked
swift test --quiet

# --- Build ------------------------------------------------------------------
step "Archive $app_name $version ($build_number)"
rm -rf "$out"
mkdir -p "$out"
xcodegen generate --spec App/project.yml --quiet
sign_settings=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" "DEVELOPMENT_TEAM=$team" "OTHER_CODE_SIGN_FLAGS=--timestamp")
[ $dry -eq 1 ] && sign_settings=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=-" DEVELOPMENT_TEAM=)
xcodebuild archive -quiet \
  -project App/FMScriptPaste.xcodeproj -scheme FMScriptPaste -configuration Release \
  -archivePath "$out/FMScriptPaste.xcarchive" -derivedDataPath "$out/DerivedData" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" "${sign_settings[@]}"

step "Export"
if [ $dry -eq 1 ]; then
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
plist="$app/Contents/Info.plist"
echo "Built $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist"))"

# --- DMG --------------------------------------------------------------------
step "DMG"
dmg="$out/FM-Script-Paste-$version.dmg"
staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "$app_name $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
echo "$dmg"

if [ $dry -eq 1 ]; then
  step "Dry run done: $dmg (ad-hoc signed, not notarised, not published)"
  exit 0
fi

codesign --sign "$identity" --timestamp "$dmg"

# --- Notarise ----------------------------------------------------------------
step "Notarise"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature -vv "$dmg"

# --- Appcast -------------------------------------------------------------------
step "Sparkle appcast"
generate_appcast="$(find "$out/DerivedData/SourcePackages/artifacts" -path '*Sparkle/bin/generate_appcast' -type f | head -1)"
[ -x "$generate_appcast" ] || { echo "error: generate_appcast not found" >&2; exit 1; }
mkdir -p "$out/updates"
cp "$dmg" "$out/updates/"
"$generate_appcast" --download-url-prefix "https://github.com/$repo/releases/download/$tag/" \
  --link "https://github.com/$repo" -o "$out/appcast.xml" "$out/updates"

# --- Publish -----------------------------------------------------------------
step "GitHub Release $tag"
git tag -a "$tag" -m "$app_name $version"
git push origin "$tag"
gh release create "$tag" "$dmg" "$out/appcast.xml" --repo "$repo" \
  --title "$app_name $version" --generate-notes
step "Released $tag"
