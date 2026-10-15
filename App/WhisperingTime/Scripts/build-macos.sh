#!/bin/bash
set -euo pipefail

if [[ "$#" -gt 2 ]]; then
  printf '%s\n' '用法：build-macos.sh [Debug|Release] [DerivedData目录]' >&2
  exit 1
fi

project_root="$(cd "$(dirname "$0")/../../.." && pwd)"
configuration="${1:-Debug}"
derived_dir="${2:-$project_root/TMP/本机构建/DerivedData}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# 共享 scheme 内的 WhisperingTime 汇总 target 会在签名完成后更新桌面替身。
xcodebuildmcp macos build \
  --project-path "$project_root/App/WhisperingTime/WhisperingTime.xcodeproj" \
  --scheme WhisperingTime --configuration "$configuration" \
  --derived-data-path "$derived_dir"
