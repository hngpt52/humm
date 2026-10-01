#!/usr/bin/env bash
# Builds Humm and packs it into build/Humm-<version>.dmg: the app beside a shortcut to
# Applications, to drag it across. One app for Apple silicon and Intel, signed as
# scripts/build.sh signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh --universal
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Humm/Info.plist)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto build/Humm.app "$STAGE/Humm.app"
ln -s /Applications "$STAGE/Applications"
DMG="build/Humm-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Humm $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null 2>&1
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' ')), SHA-256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
