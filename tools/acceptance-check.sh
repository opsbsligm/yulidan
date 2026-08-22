#!/bin/bash
# P0 实机验收辅助：会话工作区（P0.1.5 消费端）落盘核验（只读，不写任何文件）
# 用法：
#   1) 在 App 中新建会话 → 让 Agent 写相对路径文件（如「把内容 ws-check 写入 check.txt」）
#   2) 运行本脚本 → 输出最近会话工作区目录与落盘文件清单
set -euo pipefail
ROOT="$HOME/Library/Application Support/Harness"
AGENTS="$ROOT/agents"

echo "== 本地工作区根: $ROOT"
if [ ! -d "$AGENTS" ]; then
  echo "❌ agents/ 不存在（本地模式未物化？）"; exit 1
fi
echo
echo "== 最近 5 个会话工作区目录（agents/<sessionID>/）："
# shellcheck disable=SC2012  # 目录名=会话 UUID（纯 ASCII），ls 安全且需按 mtime 排序
ls -1t "$AGENTS" | head -5 | while read -r d; do
  echo "  $d  ($(find "$AGENTS/$d" -type f | wc -l | tr -d ' ') 个文件)"
done
echo
echo "== 全部工作区落盘文件："
if find "$AGENTS" -type f | grep -q .; then
  find "$AGENTS" -type f -exec ls -la {} \;
else
  echo "  （暂无 — 尚未在会话中用相对路径写入过文件）"
fi
echo
echo "== check.txt 验证（验收项）："
f=$(find "$AGENTS" -name check.txt 2>/dev/null | head -1 || true)
if [ -n "$f" ]; then
  echo "✅ 找到: $f"
  echo "--- 内容 ---"; cat "$f"
else
  echo "⏳ 未找到 check.txt — 先在 App 会话中让 Agent 写相对路径 check.txt，再重跑本脚本"
fi
