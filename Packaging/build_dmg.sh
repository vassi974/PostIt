#!/usr/bin/env bash
# build_dmg.sh — construit PostIt.app en Release puis l'empaquette dans un
# .dmg pret a distribuer (glisser dans Applications).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Build Release =="
xcodebuild -project PostIt.xcodeproj -scheme PostIt -configuration Release \
  -derivedDataPath Packaging/build clean build

APP="Packaging/build/Build/Products/Release/PostIt.app"
if [ ! -d "$APP" ]; then
  echo "App introuvable : $APP" >&2
  exit 1
fi

echo "== Signature (identité stable — préserve les permissions Accessibilité) =="
codesign --force --deep --sign "TurzxDeck Local Dev" "$APP"

echo "== Assemblage du .dmg =="
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG_NAME="Packaging/PostIt-${VERSION}.dmg"
rm -f "$DMG_NAME"

hdiutil create -volname "PostIt" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING"

echo "== Termine =="
echo "Fichier : $PWD/$DMG_NAME"
