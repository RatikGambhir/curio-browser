#!/usr/bin/env bash
# Builds Curio.app (and optionally a .dmg) for macOS.
#
#   script/bundle-macos.sh            # release build for this Mac's architecture
#   script/bundle-macos.sh --universal # Apple Silicon + Intel universal binary
#   script/bundle-macos.sh --dmg       # also create dist/Curio.dmg
#
# The app is ad-hoc signed so it runs locally. To distribute it, sign with a
# Developer ID certificate (set CURIO_SIGN_IDENTITY) and notarize it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UNIVERSAL=0
DMG=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --dmg) DMG=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Curio.app can only be bundled on macOS." >&2
  exit 1
fi

VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)"
APP="dist/Curio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ $UNIVERSAL -eq 1 ]]; then
  rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null
  cargo build --release -p curio-app --target aarch64-apple-darwin
  cargo build --release -p curio-app --target x86_64-apple-darwin
  lipo -create -output "$APP/Contents/MacOS/Curio" \
    target/aarch64-apple-darwin/release/curio \
    target/x86_64-apple-darwin/release/curio
else
  cargo build --release -p curio-app
  cp target/release/curio "$APP/Contents/MacOS/Curio"
fi

cp assets/brand/Curio.icns "$APP/Contents/Resources/Curio.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Curio</string>
  <key>CFBundleDisplayName</key><string>Curio</string>
  <key>CFBundleIdentifier</key><string>app.curio.browser</string>
  <key>CFBundleExecutable</key><string>Curio</string>
  <key>CFBundleIconFile</key><string>Curio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><false/>
  <key>NSCameraUsageDescription</key><string>Websites you allow can use your camera, for example for video calls.</string>
  <key>NSMicrophoneUsageDescription</key><string>Websites you allow can use your microphone, for example for video calls.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Websites you allow can use your location.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Web site URL</string>
      <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
      <key>LSHandlerRank</key><string>Default</string>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>HTML document</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key><array><string>public.html</string><string>public.xhtml</string></array>
      <key>LSHandlerRank</key><string>Alternate</string>
    </dict>
  </array>
</dict>
</plist>
PLIST

IDENTITY="${CURIO_SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP" 2>/dev/null \
  || codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Built $APP (version $VERSION)"

if [[ $DMG -eq 1 ]]; then
  rm -f dist/Curio.dmg
  hdiutil create -volname "Curio" -srcfolder "$APP" -ov -format UDZO dist/Curio.dmg >/dev/null
  echo "Built dist/Curio.dmg"
fi
