#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFST_REPO="${CFST_REPO:-XIU2/CloudflareSpeedTest}"
ASSET_CANDIDATES="${CFST_ARM64_ASSETS:-cfst_darwin_arm64.zip,CloudflareST_darwin_arm64.zip}"
FORCE_PACKAGE="${CFST_FORCE_PACKAGE:-false}"

emit() {
  local key="$1"
  local value="$2"
  echo "$key=$value"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$key=$value" >> "$GITHUB_OUTPUT"
  fi
}

current_version_from_package_script() {
  local package_script="$ROOT_DIR/Scripts/package_app.sh"
  local version
  version="$(sed -nE 's/^CFST_VERSION="\$\{CFST_VERSION:-([^}]+)\}"$/\1/p' "$package_script" | head -1)"
  if [[ -z "$version" ]]; then
    version="$(sed -nE 's/^CFST_VERSION="([^"]+)".*$/\1/p' "$package_script" | head -1)"
  fi
  echo "$version"
}

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available" >&2
    return 1
  fi
}

api_url="${GITHUB_API_URL:-https://api.github.com}/repos/$CFST_REPO/releases/latest"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl_headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: CFST-Manager-Upstream-Watch")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

release_json="$tmp_dir/release.json"
curl -fsSL "${curl_headers[@]}" "$api_url" -o "$release_json"

latest_version=""
asset_name=""
asset_url=""
while IFS='=' read -r key value; do
  case "$key" in
    latest_version) latest_version="$value" ;;
    asset_name) asset_name="$value" ;;
    asset_url) asset_url="$value" ;;
  esac
done < <(python3 - "$release_json" "$ASSET_CANDIDATES" <<'PY'
import json
import sys

release_path = sys.argv[1]
candidates = [item.strip() for item in sys.argv[2].split(",") if item.strip()]

with open(release_path, "r", encoding="utf-8") as handle:
    release = json.load(handle)

tag = release.get("tag_name", "")
assets = {
    asset.get("name", ""): asset.get("browser_download_url", "")
    for asset in release.get("assets", [])
}

for candidate in candidates:
    if candidate in assets and assets[candidate]:
        print(f"latest_version={tag}")
        print(f"asset_name={candidate}")
        print(f"asset_url={assets[candidate]}")
        break
else:
    print(f"Could not find any candidate asset: {','.join(candidates)}", file=sys.stderr)
    sys.exit(1)
PY
)

current_version="${CFST_CURRENT_VERSION:-$(current_version_from_package_script)}"
if [[ ! "$latest_version" =~ ^v[0-9]+(\.[0-9]+)*([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "Unexpected CloudflareSpeedTest release tag: $latest_version" >&2
  exit 1
fi
update_available="false"
if [[ "$latest_version" != "$current_version" ]]; then
  update_available="true"
fi

emit current_version "$current_version"
emit latest_version "$latest_version"
emit cfst_version "$latest_version"
emit asset_name "$asset_name"
emit update_available "$update_available"
emit download_url "$asset_url"

if [[ "$update_available" != "true" && "$FORCE_PACKAGE" != "true" ]]; then
  emit sha256 ""
  echo "CloudflareSpeedTest is already current: $current_version" >&2
  exit 0
fi

asset_path="$tmp_dir/$asset_name"
curl -fsSL --connect-timeout 20 --max-time 180 --retry 3 --retry-delay 2 "$asset_url" -o "$asset_path"
asset_sha256="$(sha256_file "$asset_path")"
emit sha256 "$asset_sha256"
