#!/bin/zsh
# 重建 HarnessApp 可执行文件并同步 .app bundle（本地开发用，P2 铁律流程化：2026-08-26 两次实锤「SPM 增量构建不刷新 bundle」后固化）
# 用法:
#   tools/rebuild-app.sh [relaunch]      构建 → cp → sha 断言 → ad-hoc 重签 → 写同步戳 →（可选）重启
#   tools/rebuild-app.sh verify [符号]    仅核验：bundle 是否落后于构建产物 +（可选）nm 符号在位探测
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=".build/arm64-apple-macosx/debug"
APP="$BUILD/HarnessApp.app"
SRC="$BUILD/HarnessApp"
BUNDLE_BIN="$APP/Contents/MacOS/HarnessApp"
STAMP="$BUILD/.bundle-sync.stamp"

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

sync_bundle() {
  swift build
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$SRC" "$BUNDLE_BIN"
  # 关键断言：cp 后 pre-sign sha 必须一致（防静默失败/旧产物）
  local a b
  a="$(sha256 "$SRC")"; b="$(sha256 "$BUNDLE_BIN")"
  if [ "$a" != "$b" ]; then
    echo "❌ bundle 同步失败：cp 后 sha 不一致（src=$a bundle=$b）"; exit 1
  fi
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
  # 同步戳：pre-sign sha + git HEAD + 时间（verify 用；签名会改写二进制 sha，故以 pre-sign 值对拍）
  printf 'src_sha=%s\nhead=%s\ntime=%s\n' "$a" "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" "$(date '+%Y-%m-%d %H:%M:%S')" > "$STAMP"
  echo "OK: $APP（sha ${a:0:12}… @ $(git rev-parse --short HEAD 2>/dev/null || echo no-git)）"
}

verify_bundle() {
  local symbol="${1:-}"
  if [ ! -f "$STAMP" ]; then
    echo "⚠️ 无同步戳（$STAMP）：bundle 未经验证，先跑 tools/rebuild-app.sh"
    if [ -n "$symbol" ]; then probe_symbol "$symbol"; fi
    exit 1
  fi
  local stamp_sha head time_
  stamp_sha="$(sed -n 's/^src_sha=//p' "$STAMP")"
  head="$(sed -n 's/^head=//p' "$STAMP")"
  time_="$(sed -n 's/^time=//p' "$STAMP")"
  local cur
  cur="$(sha256 "$SRC")"
  if [ "$cur" != "$stamp_sha" ]; then
    echo "❌ bundle 落后：构建产物已变化（stamp $stamp_sha → 现 $cur，同步于 $time_ @ $head）— 启动前必须先 tools/rebuild-app.sh"
  else
    echo "✅ bundle 与构建产物一致（$time_ @ $head）"
  fi
  if [ -n "$symbol" ]; then probe_symbol "$symbol"; fi
}

probe_symbol() {
  local symbol="$1" n
  n="$(nm -U "$BUNDLE_BIN" 2>/dev/null | grep -c "$symbol" || true)"
  if [ "$n" -gt 0 ]; then
    echo "✅ 符号 $symbol 在位（×$n）"
  else
    echo "❌ 符号 $symbol 不在 bundle 二进制（源码已改但 bundle 未同步？）"
    exit 1
  fi
}

relaunch_app() {
  local p
  p="$(pgrep -f "HarnessApp.app/Contents/MacOS/HarnessApp" || true)"
  if [ -n "$p" ]; then
    kill $p && sleep 1
  fi
  open "$APP"
  echo "relaunched"
}

case "${1:-sync}" in
  sync)
    sync_bundle
    if [ "${2:-}" = "relaunch" ]; then relaunch_app; fi
    ;;
  relaunch)
    # 兼容旧用法：tools/rebuild-app.sh relaunch = 同步 + 重启
    sync_bundle
    relaunch_app
    ;;
  verify)
    verify_bundle "${2:-}"
    ;;
  *)
    echo "用法: tools/rebuild-app.sh [sync|verify|relaunch] [relaunch|符号名]"; exit 2
    ;;
esac
