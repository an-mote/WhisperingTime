#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../../.." && pwd)"
package_date="$(date +%F)"
output_dir="$project_root/TMP/安装包/$package_date"
derived_dir="$project_root/TMP/SwiftUI迁移/$package_date/ReleaseDerivedData"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$output_dir"

xcodebuildmcp macos build \
  --project-path "$project_root/App/WhisperingTime/WhisperingTime.xcodeproj" \
  --scheme WhisperingTime --configuration Release --arch arm64 \
  --derived-data-path "$derived_dir" --output json > "$output_dir/原生Release构建.json"

app_path="$derived_dir/Build/Products/Release/WhisperingTime.app"
codesign --verify --deep --strict "$app_path"
release_entitlements="$(codesign -d --entitlements - "$app_path" 2>/dev/null)"
if [[ "$release_entitlements" == *"com.apple.security.get-task-allow"* ]]; then
  printf '%s\n' 'Release 包仍包含调试授权，已停止打包。' >&2
  exit 1
fi
stage_dir="$(mktemp -d "$output_dir/原型镜像内容.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
ditto "$app_path" "$stage_dir/印迹.app"
ln -s /Applications "$stage_dir/Applications"
cat > "$stage_dir/使用说明.txt" <<'EOF'
印迹 · SwiftUI 交互原型 0.1.0

需要 Apple Silicon Mac，macOS 26 或以上。
将“印迹.app”拖到 Applications，或直接从镜像打开体验。

先看看示例，再留下自己的测试印迹。
正文默认文字，标题与分类可选；可添加图片、原声、设备端转写和刻度。
按 ⌘N 补记、⌘S 保存；播放时方向键翻页、空格播放／暂停、Esc退出。

测试资料仅保存在本机，尚未加密。
同步页面为规则演示；真实同步、正式备份与旧数据导入尚未接入。
录音需要输入设备及麦克风权限；没有麦克风仍可导入音频。
中文识别使用设备端系统模型，原声不上传。

此镜像是本机构建并签名的原型，尚未公证或上架。
EOF

dmg_path="$output_dir/印迹-0.1.0-macOS原型.dmg"
hdiutil create -volname "印迹原型" -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path"
hdiutil verify "$dmg_path"

swift - "$dmg_path" "$HOME/Desktop/印迹 安装包.dmg" <<'SWIFT'
import Foundation
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let alias = URL(fileURLWithPath: CommandLine.arguments[2])
if FileManager.default.fileExists(atPath: alias.path) {
    guard try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true else {
        fatalError("桌面已有同名普通文件，保留原文件并停止创建替身。")
    }
    try FileManager.default.removeItem(at: alias)
}
let bookmark = try source.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
try URL.writeBookmarkData(bookmark, to: alias)
let resolved = try URL(resolvingAliasFileAt: alias)
guard resolved.standardizedFileURL == source.standardizedFileURL else { fatalError("替身目标校验失败") }
guard try alias.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile == true else { fatalError("未生成 Finder 替身") }
print("桌面替身已核对：\(alias.path)")
print("安装镜像：\(source.path)")
SWIFT
