#!/usr/bin/env bash
#
# Builds the menu-bar app and wraps it into a proper macOS .app bundle
# (menu-bar agent, no Dock icon). Run from the package root:
#
#   ./scripts/make-app.sh
#
# Produces: build/BMW ENET Forwarder.app
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="BMW ENET Forwarder"
BUNDLE_ID="com.local.enetforward"
EXECUTABLE="enetforwardapp"
OUT_DIR="build"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"

echo "==> Building ${EXECUTABLE} (release)…"
swift build -c release --product "${EXECUTABLE}"

BIN_PATH="$(swift build -c release --product "${EXECUTABLE}" --show-bin-path)/${EXECUTABLE}"

echo "==> Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>${EXECUTABLE}</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "==> Done: ${APP_DIR}"
echo "    Open it with:  open \"${APP_DIR}\""
echo "    (Gatekeeper: right-click → Open the first time, since it is unsigned.)"
