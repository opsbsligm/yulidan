#!/bin/zsh
# 三大门禁（leaks/main/xcode）一次性清偿载体 —— 仅限用户缺席>60min 窗口执行（㊻ 纪律，静默铁律 A 层）
# 启动（缺席窗口内）：cp tools/launchd/com.harness.restci.plist ~/Library/LaunchAgents/ \
#   && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.harness.restci.plist
# 终态判据：/tmp/ci_g3_rest.log 出现 ALLDONE 行；每门禁 rc 随行落账
# 收尾（惯例）：launchctl bootout gui/$(id -u)/com.harness.restci && rm LaunchAgents 内 plist（rm 被策略拒则 mv 回 tools/launchd/）
set -u
cd /Users/liguangming/code/swift-harness
LOG=/tmp/ci_g3_rest.log
: > "$LOG"   # 截断防伪指纹
echo "SWEEP-START $(date '+%F %T') HEAD=$(git rev-parse --short HEAD)" >> "$LOG"
zsh tools/ci-local.sh leaks >> "$LOG" 2>&1; echo "leaks-rc=$?" >> "$LOG"
zsh tools/ci-local.sh main  >> "$LOG" 2>&1; echo "main-rc=$?"  >> "$LOG"
zsh tools/ci-local.sh xcode >> "$LOG" 2>&1; echo "xcode-rc=$?" >> "$LOG"
echo "ALLDONE $(date '+%F %T')" >> "$LOG"
