#!/usr/bin/env bash
# Build Humm.app into build/. With --install, also copy it to /Applications (where Spotlight
# and Launchpad find it) and relaunch it from there. With --universal, build for both Apple
# silicon and Intel (for releases; needs Xcode, not just the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL=false
ARCHS=""
for option in "$@"; do
  case "$option" in
    --install) INSTALL=true ;;
    --universal) ARCHS="--arch arm64 --arch x86_64" ;;
    *) echo "Unknown option: $option" >&2; exit 2 ;;
  esac
done
# shellcheck disable=SC2086  # ARCHS is meant to split into words
swift build -c release --package-path Humm $ARCHS
# shellcheck disable=SC2086
BIN=$(swift build -c release --package-path Humm $ARCHS --show-bin-path)
APP=build/Humm.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Humm" "$APP/Contents/MacOS/Humm"
cp Humm/Info.plist "$APP/Contents/Info.plist"
cp Humm/Resources/Humm.icns "$APP/Contents/Resources/Humm.icns"  # redraw: scripts/make-icon.swift
# Prefer a stable identity: macOS ties Accessibility and microphone grants to it, so they
# survive rebuilds. Ad-hoc signatures change on every build and lose those grants.
IDENTITY=$(security find-identity -p codesigning | awk '/"Humm Dev"/ {print $2; exit}')
[ -z "$IDENTITY" ] && IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Built $APP (signed: $(security find-identity -p codesigning | awk -v h="$IDENTITY" '$2==h {sub(/^[^"]*"/,""); sub(/".*/,""); print; exit}'))"
else
  codesign --force --sign - "$APP"
  echo "Built $APP (signed: ad-hoc; Accessibility and microphone must be re-granted after each build)"
fi

if [ "$INSTALL" = true ]; then
  TARGET=/Applications/Humm.app
  if [ -d "$TARGET" ] && [ "$(defaults read "$TARGET/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" != "com.kyser.humm" ]; then
    echo "$TARGET exists and is not this app; not replacing it." >&2
    exit 1
  fi
  pkill -x Humm 2>/dev/null && sleep 0.5 || true
  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  open "$TARGET"
  echo "Installed to $TARGET and launched"
fi
