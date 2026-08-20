#!/bin/zsh
# 重建 HarnessApp 可执行文件并生成 .app 壳（本地开发用）
# 用法: ./tools/rebuild-app.sh [relaunch]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
APP=".build/arm64-apple-macosx/debug/HarnessApp.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/debug/HarnessApp "$APP/Contents/MacOS/HarnessApp"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Harness</string>
    <key>CFBundleDisplayName</key><string>Harness</string>
    <key>CFBundleIdentifier</key><string>com.deepseek.harness</string>
    <key>CFBundleVersion</key><string>0.2.0</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleExecutable</key><string>HarnessApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSUbiquitousContainerIdentifiers</key>
    <array>
        <string>iCloud.com.deepseek.harness</string>
    </array>
</dict>
</plist>
PLIST
# ad-hoc 签名带 entitlements（SSO/iCloud 描述文件就绪后真机生效；缺失时运行时优雅降级）
codesign --force --sign - --entitlements Apps/HarnessApp/HarnessApp.ci.entitlements "$APP" >/dev/null 2>&1 || true
echo "OK: $APP"

if [ "${1:-}" = "relaunch" ]; then
    P=$(pgrep -f "HarnessApp.app/Contents/MacOS/HarnessApp" || true)
    [ -n "$P" ] && kill $P && sleep 1
    open "$APP"
    echo "relaunched"
fi
