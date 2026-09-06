#!/bin/zsh
# 走测工具链可复现构建（README 的「有源可重建」从此有实据；bin/ax.bin 无源，仅由 wrapper 包住）
# 用法：zsh tools/r1walk/build.sh    （只重建有源的四个，逐个 rc 可查）
set -u
cd "${0:A:h}"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
for pair in "ev.swift ev" "evtype.swift evtype" "axdump.swift axdump" "wl.swift wl" "lockprobe2.swift lockprobe2"; do
  src="${pair%% *}"; out="${pair##* }"
  if swiftc -O "$src" -o "bin/$out" 2>/tmp/r1walk_build_${out}.log; then
    echo "✅ $out"
  else
    echo "❌ $out（见 /tmp/r1walk_build_${out}.log）"
    exit 1
  fi
done
echo "注：bin/ax.bin 无源（历史遗失），其闸门在 bin/ax wrapper 里，不经本脚本重建。"
