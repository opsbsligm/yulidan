#!/usr/bin/env bash
# runq.sh —— 跑一条命令并把「完整输出 + 真实退出码」一次性落盘（09-06 QUALITY ㊵-4 的直接产物）。
#
# 存在理由：同一条坑入册两次后我又踩了第三次（`echo "...${PIPESTATUS[0]}"` 取不到 rc）。
# 结论：**靠「请记住」防不住的失误必须改成工具**——本脚本让调用方永远不需要 PIPESTATUS／$?，
# 退出码由本脚本原样透传，完整输出落盘，取证只认落盘物。
#
# 用法：tools/qa/runq.sh <日志路径> <命令> [参数...]
# 退出码：被测命令的退出码原样透传；参数不足 = 2（响亮失败，绝不静默当作成功）。
# 附产：日志文件含命令原文、起止时间、退出码；另在 stderr 打一行 `runq: RC=<n> LOG=<path>`。
set -uo pipefail
if [ "$#" -lt 2 ]; then   # ← 自测抓到：原写 -lt 3 会把最常见的两参数调用（log＋cmd）误判为用法错误
  echo "用法: $0 <日志路径> <命令> [参数...]（参数不足即报错，不允许空跑）" >&2
  exit 2
fi
LOG="$1"; shift
: > "$LOG" || { echo "runq: 日志不可写：$LOG" >&2; exit 2; }
{
  echo "# runq @ $(date '+%F %T')"
  echo "# cmd: $*"
  echo "# ---- output below ----"
} >> "$LOG"
"$@" >> "$LOG" 2>&1
rc=$?                       # ← 唯一可信的取码方式：紧跟命令，不经过任何管道
{
  echo "# ---- output above ----"
  echo "RC=$rc"
} >> "$LOG"
echo "runq: RC=$rc LOG=$LOG" >&2
exit "$rc"
