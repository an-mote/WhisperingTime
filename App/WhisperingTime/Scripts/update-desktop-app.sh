#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  printf '%s\n' '用法：update-desktop-app.sh /path/to/WhisperingTime.app' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/../../.." && pwd)"
publication_root="$project_root/TMP/本机构建/桌面应用"
module_cache="$project_root/TMP/本机构建/SwiftModuleCache"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$module_cache"

exec /usr/bin/swift -module-cache-path "$module_cache" \
  "$script_dir/update-desktop-app.swift" \
  "$1" "$publication_root" "$HOME/Desktop/印迹.app"
