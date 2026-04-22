#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build/macos-apps"
FINAL_DIR="$BUILD_DIR/final"
TMP_DIR="$BUILD_DIR/tmp"
IDENTITY_DEFAULT='Developer ID Application: Chaojifeng (Xiamen) Network Technology Co., Ltd. (DYGN8HZFL9)'
IDENTITY="${CODESIGN_IDENTITY:-$IDENTITY_DEFAULT}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
TEAM_ID="${TEAM_ID:-DYGN8HZFL9}"

mkdir -p "$BUILD_DIR" "$FINAL_DIR" "$TMP_DIR"
rm -rf "$TMP_DIR"/* "$FINAL_DIR"/*

create_icns() {
  local src_png="$1"
  local out_icns="$2"
  local base
  base="$(mktemp -d "$TMP_DIR/iconset.XXXXXX")"
  local iconset="$base/AppIcon.iconset"
  mkdir -p "$iconset"

  sips -z 16 16     "$src_png" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32     "$src_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$src_png" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64     "$src_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$src_png" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256   "$src_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$src_png" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512   "$src_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$src_png" --out "$iconset/icon_512x512.png" >/dev/null
  cp "$src_png" "$iconset/icon_512x512@2x.png"

  iconutil -c icns "$iconset" -o "$out_icns"
}

create_app() {
  local app_name="$1"
  local bundle_id="$2"
  local src_script="$3"
  local icon_png="$4"
  local app_dir="$TMP_DIR/$app_name.app"
  local contents="$app_dir/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  mkdir -p "$macos" "$resources"

  cp "$src_script" "$resources/installer.command"
  chmod 755 "$resources/installer.command"

  cat > "$macos/launcher" <<'EOS'
#!/bin/bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$APP_DIR/Resources/installer.command"
chmod 755 "$SCRIPT_PATH"
open -a Terminal "$SCRIPT_PATH"
EOS
  chmod 755 "$macos/launcher"

  create_icns "$icon_png" "$resources/AppIcon.icns"

  cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  /usr/libexec/PlistBuddy -c "Print" "$contents/Info.plist" >/dev/null
  echo "$app_dir"
}

sign_notarize_zip() {
  local app_dir="$1"
  local zip_name="$2"
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$app_dir"
  codesign --verify --deep --strict --verbose=2 "$app_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$TMP_DIR/$zip_name"
  xcrun notarytool submit "$TMP_DIR/$zip_name" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app_dir"
  spctl --assess --type execute -vv "$app_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$FINAL_DIR/$zip_name"
}

GLM_APP=$(create_app "智谱 Claude Code 安装器" "com.chaojifeng.glm-claude-installer" "$REPO_DIR/scripts/macos/install-glm-claude.command" "$REPO_DIR/assets/rendered/zai-logo.svg.png")
CODEX_APP=$(create_app "OpenAI Codex 安装器" "com.chaojifeng.openai-codex-installer" "$REPO_DIR/scripts/macos/install-openai-codex.command" "$REPO_DIR/assets/rendered/codex-color.png")

sign_notarize_zip "$GLM_APP" "智谱-Claude-Code-安装器-macOS.zip"
sign_notarize_zip "$CODEX_APP" "OpenAI-Codex-安装器-macOS.zip"

echo "\nFinal artifacts:"
find "$FINAL_DIR" -maxdepth 1 -type f | sort
