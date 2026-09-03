#!/bin/zsh
# RSS/CPU 静默采样器（A 层：ps 只读，零打扰，锁屏可跑）——PERFORMANCE.md 平台期规则配套
# 用法: tools/perf/rss-sample.sh [标签]   （输出时刻/RSS_MB/pcpu/进程龄/bundle_sha，供平台期表登记）
APP=${HARNESS_APP:-/Users/liguangming/code/swift-harness/ci-derived-data/Build/Products/Debug/Harness.app}
LABEL=${1:-manual}
PID=$(pgrep -x Harness | head -1)
if [[ -z "$PID" ]]; then echo "no HarnessApp process; start with: open -g -j '$APP'"; exit 2; fi
read -r RSS PCPU ELAPSED <<<"$(ps -o rss=,pcpu=,etime= -p "$PID" | awk '{print $1, $2, $3}')"
SHA=$(shasum -a 256 "$APP/Contents/MacOS/Harness" 2>/dev/null | cut -c1-8)
echo "$(date '+%H:%M:%S') label=$LABEL pid=$PID rss_mb=$(python3 -c "print(round($RSS/1024,1))") pcpu=$PCPU age=$ELAPSED bundle_sha=$SHA"
