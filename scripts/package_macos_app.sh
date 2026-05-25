#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Moon Bridge"
BUILD_DIR="${ROOT_DIR}/dist/macos"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SERVICE_BIN="${RESOURCES_DIR}/moonbridge"
LAUNCHER_BIN="${MACOS_DIR}/MoonBridgeLauncher"
SWIFT_SRC_DIR="${ROOT_DIR}/desktop/macos/MoonBridgeLauncher/Sources"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS." >&2
  exit 1
fi

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "Building Moon Bridge service..."
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o "${TMP_DIR}/moonbridge-arm64" ./cmd/moonbridge
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "${TMP_DIR}/moonbridge-amd64" ./cmd/moonbridge
lipo -create "${TMP_DIR}/moonbridge-arm64" "${TMP_DIR}/moonbridge-amd64" -output "${SERVICE_BIN}"
chmod 755 "${SERVICE_BIN}"

echo "Building macOS launcher..."
SWIFT_SOURCES=()
while IFS= read -r source_file; do
  SWIFT_SOURCES+=("${source_file}")
done < <(find "${SWIFT_SRC_DIR}" -name '*.swift' -print | sort)
swiftc "${SWIFT_SOURCES[@]}" \
  -parse-as-library \
  -O \
  -target arm64-apple-macos13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -o "${TMP_DIR}/MoonBridgeLauncher-arm64"
swiftc "${SWIFT_SOURCES[@]}" \
  -parse-as-library \
  -O \
  -target x86_64-apple-macos13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -o "${TMP_DIR}/MoonBridgeLauncher-x86_64"
lipo -create "${TMP_DIR}/MoonBridgeLauncher-arm64" "${TMP_DIR}/MoonBridgeLauncher-x86_64" -output "${LAUNCHER_BIN}"
chmod 755 "${LAUNCHER_BIN}"

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>Moon Bridge</string>
  <key>CFBundleExecutable</key>
  <string>MoonBridgeLauncher</string>
  <key>CFBundleIdentifier</key>
  <string>local.moonbridge.launcher</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Moon Bridge</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "${RESOURCES_DIR}/README.txt" <<'README'
Moon Bridge.app

首次启动会在当前用户目录下创建：
~/Library/Application Support/MoonBridge/

配置、数据库和日志都会放在这个目录。
README

if command -v codesign >/dev/null 2>&1; then
  echo "Ad-hoc signing app..."
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
fi

echo "Creating zip package..."
ditto -c -k --keepParent "${APP_DIR}" "${BUILD_DIR}/${APP_NAME}.zip"

echo "Built: ${APP_DIR}"
echo "Zip: ${BUILD_DIR}/${APP_NAME}.zip"
