#!/usr/bin/env bash
# D-23 形状守卫：`UNUserNotificationCenter.current()` 只允许出现在「惰性 provider 默认参数」行里。
# 存在理由：该 API 在裸 xctest 进程里触发 NSAssertion -> SIGABRT（实测崩溃报告
#   ~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-09-06-074954.ips），
#   而「构造时不得触碰 UN」这条不变量在测试宿主里**没有行为判据**（测试里无法合法取得 UN 中心
#   实例，任何尝试都会当场崩掉运行器）=> 只能用工件级 lint 锁形状（同 official-claim-lint 思路）。
# 退出码：0=合规；1=出现非惰性取用；2=目标文件缺失（拒绝把读不到读成合规）。
set -euo pipefail
TARGET="${1:-Packages/Notifications/Sources/NotificationService.swift}"
[ -f "$TARGET" ] || { echo "❌ 目标文件不存在：${TARGET}" >&2; exit 2; }
python3 - "$TARGET" <<'LPY'
import io, re, sys
path = sys.argv[1]
allowed = re.compile(r"center:\s*@escaping\s*@Sendable\s*\(\)\s*->\s*UNUserNotificationCenter.*UNUserNotificationCenter\.current\(\)")
bad = []
for no, line in enumerate(io.open(path, encoding="utf-8"), 1):
    stripped = line.strip()
    # 跳过注释行：本仓注释会**引用**旧写法作反面教材（实测我自己的 D-23 注释就触发了本守卫，
    # 与 QUALITY ⑮「自检查了注释文本里的 token」同族坑 ⇒ 判据只看代码行）
    if stripped.startswith("//") or stripped.startswith("///"):
        continue
    if "UNUserNotificationCenter.current()" not in line:
        continue
    if allowed.search(line):
        continue
    bad.append((no, line.strip()))
if bad:
    print("❌ %s: %d 处非惰性取用 UNUserNotificationCenter（构造即崩测试运行器）" % (path, len(bad)), file=sys.stderr)
    for no, text in bad:
        print("   %s:%d  %s" % (path, no, text[:110]), file=sys.stderr)
    sys.exit(1)
print("✅ %s: UNUserNotificationCenter 取用全部惰性（形状守卫通过）" % path)
LPY
