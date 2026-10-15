#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf '%s\n' '用法：test-desktop-app.sh <已签名的 WhisperingTime.app>' >&2
  exit 1
fi
script_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_root="$(cd "$script_dir/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fixture="$1"
/usr/bin/codesign --verify --deep --strict "$fixture"
mkdir -p "$project_root/TMP/桌面替身验证"
test_root="$(mktemp -d "$project_root/TMP/桌面替身验证/测试.XXXXXX")"
publication_root="$test_root/已发布"
desktop="$test_root/桌面"
alias_path="$desktop/印迹.app"
mkdir -p "$desktop"
module_cache="$test_root/SwiftModuleCache"
mkdir -p "$module_cache"

publish() {
  /usr/bin/swift -module-cache-path "$module_cache" "$script_dir/update-desktop-app.swift" "$1" "$publication_root" "$alias_path"
}
resolve_alias() {
  /usr/bin/swift -module-cache-path "$module_cache" - "$alias_path" <<'SWIFT'
import Foundation
let alias = URL(fileURLWithPath: CommandLine.arguments[1])
guard try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true else { exit(1) }
print(try URL(resolvingAliasFileAt: alias, options: [.withoutUI, .withoutMounting]).path)
SWIFT
}
expect_failure() {
  if publish "$1" > "$test_root/预期失败.log" 2>&1; then
    printf '%s\n' '错误：预期失败的发布却成功。' >&2
    exit 1
  fi
}

publish "$fixture" > "$test_root/首次发布.log"
first_target="$(resolve_alias)"
[[ "$first_target" == "$publication_root/"*/WhisperingTime.app ]]
/usr/bin/codesign --verify --deep --strict "$first_target"
publish "$fixture" > "$test_root/替换发布.log"
second_target="$(resolve_alias)"
[[ "$second_target" != "$first_target" && -d "$first_target" ]]
/usr/bin/codesign --verify --deep --strict "$second_target"
cp "$alias_path" "$test_root/有效替身备份"

ditto "$fixture" "$test_root/坏签名.app"
printf 'invalid signature test\n' >> "$test_root/坏签名.app/Contents/MacOS/WhisperingTime"
expect_failure "$test_root/坏签名.app"
[[ "$(resolve_alias)" == "$second_target" && -d "$second_target" ]]
cmp "$alias_path" "$test_root/有效替身备份"

rm "$alias_path"
printf '保留普通文件\n' > "$alias_path"
expect_failure "$fixture"
[[ "$(cat "$alias_path")" == '保留普通文件' ]]
rm "$alias_path"
mkdir "$alias_path"
expect_failure "$fixture"
[[ -d "$alias_path" ]]
rmdir "$alias_path"
ln -s "$test_root/不存在的目标" "$alias_path"
expect_failure "$fixture"
[[ -L "$alias_path" && "$(readlink "$alias_path")" == "$test_root/不存在的目标" ]]
rm "$alias_path"
cp "$test_root/有效替身备份" "$alias_path"
[[ "$(resolve_alias)" == "$second_target" ]]

# Two simultaneous publications must leave one complete, verifiable application.
publish "$fixture" > "$test_root/并发一.log" &
first_pid=$!
publish "$fixture" > "$test_root/并发二.log" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
final_target="$(resolve_alias)"
/usr/bin/codesign --verify --deep --strict "$final_target"
[[ -d "$first_target" && -d "$second_target" ]]
published_apps=("$publication_root"/*/WhisperingTime.app)
[[ "${#published_apps[@]}" == 4 ]]
printf 'PASS：创建、替换、Finder 替身目标、签名失败保留、文件/目录/符号链接冲突及并发发布。\n证据目录：%s\n' "$test_root"
