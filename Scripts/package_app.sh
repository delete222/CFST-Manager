#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/CFST Manager.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CFST_VERSION="${CFST_VERSION:-v2.3.5}"
CFST_ARM64_ASSETS="${CFST_ARM64_ASSETS:-cfst_darwin_arm64.zip,CloudflareST_darwin_arm64.zip}"
CFST_ARM64_SHA256="${CFST_ARM64_SHA256:-0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc}"
DOWNLOAD_ROOT_DIR="${CFST_DOWNLOAD_DIR:-$DIST_DIR}"
DOWNLOAD_DIR="$DOWNLOAD_ROOT_DIR/$CFST_VERSION"
DEFAULT_LOCAL_ARM64_DIR="$HOME/Downloads/cfst_darwin_arm64"
LOCAL_CFST_ARM64_DIR="${LOCAL_CFST_ARM64_DIR:-}"
LOCAL_CFST_AMD64_DIR="${LOCAL_CFST_AMD64_DIR:-}"
CFST_MANAGER_FORCE_DOWNLOAD="${CFST_MANAGER_FORCE_DOWNLOAD:-0}"

mkdir -p "$DIST_DIR"
mkdir -p "$DOWNLOAD_DIR"
rm -rf "$APP_DIR"

swift build --package-path "$ROOT_DIR" -c release --product CFSTManager
BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)/CFSTManager"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/CFSTManager"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CFSTManager</string>
  <key>CFBundleIdentifier</key>
  <string>local.cfst.manager</string>
  <key>CFBundleName</key>
  <string>CFST Manager</string>
  <key>CFBundleDisplayName</key>
  <string>CFST Manager</string>
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

download_asset() {
  local assets_csv="$1"
  local expected_sha="$2"
  local asset=""
  local zip_path=""
  local url=""
  IFS=',' read -r -a assets <<< "$assets_csv"

  for candidate in "${assets[@]}"; do
    asset="$candidate"
    zip_path="$DOWNLOAD_DIR/$asset"
    url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/$CFST_VERSION/$asset"
    if [[ -f "$zip_path" ]]; then
      break
    fi
    rm -f "$zip_path"
    if curl -L --fail --connect-timeout 20 --max-time 180 --retry 3 --retry-delay 2 --output "$zip_path" "$url"; then
      break
    else
      rm -f "$zip_path"
      zip_path=""
    fi
  done

  if [[ -z "$zip_path" || ! -f "$zip_path" ]]; then
    echo "Failed to download any candidate asset: $assets_csv" >&2
    return 1
  fi

  local actual
  actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
  if [[ "$actual" != "$expected_sha" ]]; then
    echo "Checksum mismatch for $asset" >&2
    echo "expected $expected_sha" >&2
    echo "actual   $actual" >&2
    exit 1
  fi

  local extract_dir="$DIST_DIR/${asset%.zip}"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  unzip -q "$zip_path" -d "$extract_dir"
  echo "$extract_dir"
}

find_cfst_binary() {
  local extract_dir="$1"
  local binary
  binary="$(find "$extract_dir" -type f \( -name cfst -o -name CloudflareST \) -perm -111 | head -1)"
  if [[ -z "$binary" ]]; then
    binary="$(find "$extract_dir" -type f \( -name cfst -o -name CloudflareST \) | head -1)"
  fi
  if [[ -z "$binary" ]]; then
    echo "Could not find cfst/CloudflareST binary in $extract_dir" >&2
    return 1
  fi
  echo "$binary"
}

require_binary_architecture() {
  local binary="$1"
  local expected_arch="$2"
  if ! file "$binary" | grep -q "$expected_arch"; then
    echo "Architecture mismatch for $binary" >&2
    echo "Expected: $expected_arch" >&2
    file "$binary" >&2
    exit 1
  fi
}

validate_cfst_dir() {
  local directory="$1"
  [[ -f "$directory/ip.txt" && -f "$directory/ipv6.txt" ]] || return 1
  find_cfst_binary "$directory" >/dev/null
}

copy_optional_text_file() {
  local source_dir="$1"
  local file_name="$2"
  if [[ -f "$source_dir/$file_name" ]]; then
    cp "$source_dir/$file_name" "$RESOURCES_DIR/$file_name"
  fi
}

if [[ "$CFST_MANAGER_FORCE_DOWNLOAD" != "1" && -z "$LOCAL_CFST_ARM64_DIR" && -d "$DEFAULT_LOCAL_ARM64_DIR" ]]; then
  LOCAL_CFST_ARM64_DIR="$DEFAULT_LOCAL_ARM64_DIR"
fi

if [[ -n "$LOCAL_CFST_ARM64_DIR" ]]; then
  if validate_cfst_dir "$LOCAL_CFST_ARM64_DIR"; then
    ARM_DIR="$LOCAL_CFST_ARM64_DIR"
    echo "Using local arm64 CloudflareSpeedTest: $ARM_DIR"
  else
    echo "LOCAL_CFST_ARM64_DIR is missing cfst/ip.txt/ipv6.txt: $LOCAL_CFST_ARM64_DIR" >&2
    exit 1
  fi
else
  ARM_DIR="$(download_asset "$CFST_ARM64_ASSETS" "$CFST_ARM64_SHA256")"
fi

if [[ -n "$LOCAL_CFST_AMD64_DIR" ]]; then
  if validate_cfst_dir "$LOCAL_CFST_AMD64_DIR"; then
    AMD_DIR="$LOCAL_CFST_AMD64_DIR"
    echo "Using local amd64 CloudflareSpeedTest: $AMD_DIR"
  else
    echo "LOCAL_CFST_AMD64_DIR is missing cfst/ip.txt/ipv6.txt: $LOCAL_CFST_AMD64_DIR" >&2
    exit 1
  fi
else
  AMD_DIR=""
  echo "LOCAL_CFST_AMD64_DIR not set; packaging Apple Silicon cfst only."
fi

cp "$(find_cfst_binary "$ARM_DIR")" "$RESOURCES_DIR/cfst-darwin-arm64"
chmod +x "$RESOURCES_DIR/cfst-darwin-arm64"
require_binary_architecture "$RESOURCES_DIR/cfst-darwin-arm64" "arm64"
if [[ -n "$AMD_DIR" ]]; then
  cp "$(find_cfst_binary "$AMD_DIR")" "$RESOURCES_DIR/cfst-darwin-amd64"
  chmod +x "$RESOURCES_DIR/cfst-darwin-amd64"
  require_binary_architecture "$RESOURCES_DIR/cfst-darwin-amd64" "x86_64"
fi

if [[ -z "$AMD_DIR" ]]; then
  require_binary_architecture "$MACOS_DIR/CFSTManager" "arm64"
fi

cp "$ARM_DIR/ip.txt" "$RESOURCES_DIR/ip.txt"
cp "$ARM_DIR/ipv6.txt" "$RESOURCES_DIR/ipv6.txt"
copy_optional_text_file "$ARM_DIR" LICENSE
copy_optional_text_file "$ARM_DIR" README.md
copy_optional_text_file "$ARM_DIR" "使用+错误+反馈说明.txt"

if [[ ! -f "$RESOURCES_DIR/LICENSE" ]]; then
  cat > "$RESOURCES_DIR/LICENSE" <<LICENSE
CFST Manager bundles XIU2/CloudflareSpeedTest $CFST_VERSION.
The upstream project is licensed under GPL-3.0.

Full license and source:
https://github.com/XIU2/CloudflareSpeedTest
LICENSE
fi

xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

cat > "$RESOURCES_DIR/NOTICE.txt" <<NOTICE
CFST Manager bundles XIU2/CloudflareSpeedTest $CFST_VERSION.
Project: https://github.com/XIU2/CloudflareSpeedTest
License: GPL-3.0. See LICENSE in this Resources directory.
NOTICE

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
