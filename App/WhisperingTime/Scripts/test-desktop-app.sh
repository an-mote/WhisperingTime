#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
export PYTHONDONTWRITEBYTECODE=1
exec /usr/bin/env python3 "$script_dir/host-automation.py" run -- \
  /bin/bash "$script_dir/Tests/desktop-app.sh" "$@"
