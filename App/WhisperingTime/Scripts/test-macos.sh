#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/../../.." && pwd)"
configuration="${1:-Debug}"
if [[ "$#" -gt 0 ]]; then shift; fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PYTHONDONTWRITEBYTECODE=1

# 共享锁覆盖测试构建、运行和退出；忙碌时每三秒重新检查。
exec /usr/bin/env python3 "$script_dir/host-automation.py" run -- \
  xcodebuildmcp macos test \
  --project-path "$project_root/App/WhisperingTime/WhisperingTime.xcodeproj" \
  --scheme WhisperingTime --configuration "$configuration" \
  --derived-data-path "$project_root/TMP/本机测试/DerivedData" "$@"
