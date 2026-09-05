#!/bin/bash
# 静默门禁窗口守卫（铁律 8「静默验收」的工具化；此前「重门禁只在缺席窗口跑」仅靠人工判断）
# ---------------------------------------------------------------------------
# 语义：
#   1) 等待人机空闲达到阈值才启动重门禁（默认 60 分钟）；
#   2) 运行期间持续观察，一旦你回到电脑（空闲低于暂停阈值）立即中止门禁子进程组，
#      绝不与你争夺 CPU/前台（本脚本自身零前台、零输入注入，纯 CLI 子进程）；
#   3) 门禁判据本身完全委托 tools/ci-local.sh，本脚本**不替代、不降级**任何判据。
#
# 用法: tools/ci-quiet.sh [pr|leaks|xcode|main|all]
#   环境变量：
#     QUIET_IDLE_MIN   启动阈值（分钟，默认 60）
#     QUIET_PAUSE_MIN  运行中回退中止阈值（分钟，默认 5）
#     QUIET_MAX_WAIT   等待启动的最长秒数（默认 7200 = 2h，超时以 rc=5 放弃）
#     QUIET_POLL       轮询间隔秒（默认 20）
#     QUIET_CMD        替代门禁命令（仅用于自测守卫逻辑；缺省 = tools/ci-local.sh <mode>）
#     QUIET_MAX_RETRIES 因你回到电脑而中止后的重试次数（默认 2）
# 退出码：0 门禁通过 / 1 门禁失败 / 3 中止后重试耗尽 / 5 等待窗口超时
set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-pr}"
IDLE_MIN="${QUIET_IDLE_MIN:-60}"
PAUSE_MIN="${QUIET_PAUSE_MIN:-5}"
MAX_WAIT="${QUIET_MAX_WAIT:-7200}"
POLL="${QUIET_POLL:-20}"
MAX_RETRIES="${QUIET_MAX_RETRIES:-2}"
LOG="/tmp/ci_quiet.${MODE}.log"

# HIDIdleTime 单位是 ns；取 IOHIDSystem 首条（本机实测稳定；勿用 CG 接口，27beta 有幻影问题）
idle_minutes() {
  local ns
  ns=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print $NF; exit}')
  [ -z "$ns" ] && { echo "-1"; return; }
  echo $(( ns / 1000000000 / 60 ))
}

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

if [ "${2:-}" = "--check-only" ]; then
  echo "idle=$(idle_minutes)min start>=${IDLE_MIN}min pause<${PAUSE_MIN}min mode=${MODE}"
  exit 0
fi

: > "$LOG"
GATE_CMD=${QUIET_CMD:-"tools/ci-local.sh ${MODE}"}
log "静默守卫启动 mode=${MODE} 门禁命令=${GATE_CMD}"

attempt=0
while : ; do
  # ---- 阶段一：等待缺席窗口 ----
  waited=0
  while : ; do
    im=$(idle_minutes)
    if [ "$im" -lt 0 ]; then log "读取 HIDIdleTime 失败（无 IOHIDSystem？）——放弃，不盲跑门禁"; exit 5; fi
    [ "$im" -ge "$IDLE_MIN" ] && { log "缺席窗口达成：idle=${im}min ≥ ${IDLE_MIN}min"; break; }
    [ "$waited" -ge "$MAX_WAIT" ] && { log "等待超时（${MAX_WAIT}s，idle=${im}min）→ 不跑门禁，退出"; exit 5; }
    [ $(( waited % 600 )) -eq 0 ] && log "等待缺席中 idle=${im}min（需 ≥${IDLE_MIN}min）"
    sleep "$POLL"; waited=$(( waited + POLL ))
  done

  # ---- 阶段二：启动门禁并持续观察 ----
  # setsid 让门禁及其全部子进程处于独立进程组，中止时可整组回收（避免 T 态孤儿残留）
  perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV or exit 127' \
      sh -c "$GATE_CMD" >>"$LOG" 2>&1 &
  pid=$!
  log "门禁已启动 pid=${pid}（进程组长），开始监视你的活动（idle<${PAUSE_MIN}min 即中止）"

  aborted=0
  while kill -0 "$pid" 2>/dev/null; do
    im=$(idle_minutes)
    if [ "$im" -ge 0 ] && [ "$im" -lt "$PAUSE_MIN" ]; then
      log "⚠️ 你回到电脑（idle=${im}min < ${PAUSE_MIN}min）→ 立即回收门禁进程组"
      pg=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
      [ -n "$pg" ] && kill -9 "-${pg}" 2>/dev/null
      pkill -9 -P "$pid" 2>/dev/null
      kill -9 "$pid" 2>/dev/null
      aborted=1; break
    fi
    sleep "$POLL"
  done

  if [ "$aborted" = "1" ]; then
    attempt=$(( attempt + 1 ))
    [ "$attempt" -gt "$MAX_RETRIES" ] && { log "重试耗尽（${MAX_RETRIES}）→ 交回人工择时"; exit 3; }
    log "第 ${attempt} 次中止，回到等待循环"
    continue
  fi

  rc=0; wait "$pid" 2>/dev/null || rc=$?
  log "门禁结束 rc=${rc}（详见 ${LOG}）"
  exit "$rc"
done
