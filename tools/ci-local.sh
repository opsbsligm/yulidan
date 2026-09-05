#!/bin/bash
# 本地 CI 模拟（与 .github/workflows/swift-ci.yml 各 job 对齐；GitHub 远端未启用期间使用）
# 用法: tools/ci-local.sh [pr|leaks|xcode|main|all]   默认 pr
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-pr}"

# 原子完成标记（P1_STAGE_REPORT 补记⑧ 长期方案落地）：
# 任一起动即清理旧标记；失败/异常由 EXIT trap 清除；仅全部通过才写（mktemp+mv 原子）。
# 消费方（哨兵/编排脚本）以 /tmp/ci.done.<mode> 的存在+内容判定「该门禁段完成」，
# 不读轮转中的 live 日志（双链竞态教训：日志会被下一段重定向覆写，grep 判定天然撕裂）。
DONE_MARKER="/tmp/ci.done.${MODE}"
rm -f "$DONE_MARKER" "${DONE_MARKER}.tmp"
trap 'rm -f "$DONE_MARKER" "${DONE_MARKER}.tmp"' EXIT

# 全量测试看门狗：挂起（runner 存活但不退出）不会触发下方「非零退出才重试」的有界重试，
# 超过 TEST_TIMEOUT 秒由 SIGALRM 终止为 rc=142 → 正常走重试路径（经验来源：QUALITY_REPORT 2026-09-01 第六轮）
TEST_TIMEOUT=1200
# 09-05 新增有界化：xcode 收尾阶段与 leaks 均实测过「工具无返回」挂起（详见 QUALITY 09-05 条目；
#   注：同日 18:09 该轮「本机通道不可用」归因经对照实测已否证＝间歇性故障、病因未定，见 P1 补记⓬；有界化本身保留）。
# 无超时的门禁会无限滞留并留下被停住(T 态)的孤儿子进程，故一律加闹钟并显式判失败（不静默放行）。
XCODE_TEST_TIMEOUT=2400
LEAKS_TIMEOUT=300
RSS_GUARD_MAX_KB=${RSS_GUARD_MAX_KB:-524288}   # MemProbe RSS 增量护栏阈值（默认 512MB）

step() { echo; echo "===== $1 ====="; }

run_pr() {
  step "PR-0 代码注释「官方」引用断言门（门禁：0 违规；BENCHMARK §22）"
  # 09-05 新增：反过度归属从人工抽查变成常驻门。rc=1 有未挂锚断言；rc=2 口径不闭合（须重审并更新 §22.5 基线）。
  python3 tools/qa/official-claim-lint.py --root .
  step "PR-1 SwiftLint（门禁：0 违规）"
  swiftlint lint --strict --config .swiftlint.yml
  step "PR-2 SwiftFormat（门禁：0 文件需格式化）"
  swiftformat --lint . --config .swiftformat
  step "PR-3 Build（门禁：0 警告）"
  swift build 2>&1 | tee /tmp/ci_local_build.log
  if grep -qE 'warning:' /tmp/ci_local_build.log; then
    echo "❌ 发现编译警告（零警告基线破坏）"; exit 1
  fi
  step "PR-4 Unit Tests（门禁：全绿）"
  # 有界重试：macOS 存在瞬态协作池调度停滞（线程空闲但任务不派发，~10-13s，见 QUALITY_REPORT P1）；
  # 停滞属环境故障，真实回归重试仍会失败，重试一次用于区分二者
  for attempt in 1 2; do
    perl -e 'alarm shift @ARGV; exec @ARGV' "${TEST_TIMEOUT}" swift test --parallel && break
    # SIGALRM 只终止被包装的 swift-test 父进程；清理可能的孤儿 runner（watchdog 场景），正常失败路径为 no-op
    pkill -f "swift-harnessPackageTests" 2>/dev/null || true
    if [ "${attempt}" -eq 2 ]; then echo "❌ 全量测试两轮均失败"; exit 1; fi
    echo "⚠️ 首轮全量失败 — 有限重试一次（环境调度停滞容忍，非代码回归）"
  done
}

run_leaks() {
  step "LEAKS Build debug"
  swift build

  # 补充证据（不需要 task 端口，故不受本机调试通道状态影响）：外部 ps 轮询 MemProbe RSS 增长。
  # 口径注明：这是「无失控增长」护栏，**不等同** leaks 的对象图泄漏判据，不可代替其核销。
  step "LEAKS 外部 RSS 增长护栏（MemProbe 2000 迭代，ps 轮询）"
  .build/debug/MemProbe 2000 > /tmp/ci_leaks_rss.log 2>&1 &
  probe_pid=$!
  rss_first=0; rss_max=0
  for _ in 1 2 3 4 5 6 8 10 12 15 20 25 30 40 50 60; do
    rss=$(ps -o rss= -p "$probe_pid" 2>/dev/null | tr -d ' ' || true)
    [ -z "$rss" ] && break
    [ "$rss_first" -eq 0 ] && rss_first=$rss
    [ "$rss" -gt "$rss_max" ] && rss_max=$rss
    sleep 1
  done
  wait "$probe_pid" || { echo "❌ MemProbe 本体失败（见 /tmp/ci_leaks_rss.log）"; exit 1; }
  # 判据取「峰值 RSS 对绝对阈值」：首采样含进程冷启动爬坡（实测 208KB 伪低值），不可作基线算增量。
  echo "RSS 护栏：首采样=${rss_first}KB（仅参考）峰值=${rss_max}KB（阈值 ${RSS_GUARD_MAX_KB}KB）"
  [ "$rss_max" -le "$RSS_GUARD_MAX_KB" ] || { echo "❌ 峰值 RSS 超阈值，疑似失控增长"; exit 1; }

  step "LEAKS leaks --atExit MemProbe 500（期望 0 leaks；有界 ${LEAKS_TIMEOUT}s）"
  rc=0
  perl -e 'alarm shift @ARGV; exec @ARGV' "$LEAKS_TIMEOUT" leaks --atExit -- .build/debug/MemProbe 500 || rc=$?
  if [ "$rc" -eq 142 ]; then
    # leaks 超时会使目标停在 T 态并被孤儿化，必须清理，否则污染后续门禁与 ps 口径
    pkill -9 -f "MemProbe 500" 2>/dev/null || true
    echo "❌ leaks --atExit ${LEAKS_TIMEOUT}s 内无结论（病因未定：09-05 曾连续挂起，同日 18:09 同判据实测 rc=0 ⇒ 间歇性故障，非本机永久退化）"
    echo "   已通过：RSS 增长护栏（上方数值；口径不等同对象图泄漏判据，不可自审自批）。"
    echo "   处置顺序：① 查并发重门禁/高负载 → ② 直接复跑本模式 → ③ 连续 ≥3 次挂起才升级为环境事件申报（不得写成「本机不可用」）。"
    exit 142
  fi
  [ "$rc" -eq 0 ] || exit "$rc"
}

run_xcode() {
  step "XCODE Generate project"
  xcodegen generate
  step "XCODE Build (HarnessApp Debug)"
  xcodebuild -project swift-harness.xcodeproj -scheme HarnessApp -configuration Debug \
    -derivedDataPath ./ci-derived-data build
  step "XCODE Test (HarnessApp Debug)"
  rc=0
  perl -e 'alarm shift @ARGV; exec @ARGV' "$XCODE_TEST_TIMEOUT" xcodebuild -project swift-harness.xcodeproj \
    -scheme HarnessApp -configuration Debug -derivedDataPath ./ci-derived-data test || rc=$?
  if [ "$rc" -eq 142 ]; then
    echo "❌ xcodebuild test 超时无结论（有界 ${XCODE_TEST_TIMEOUT}s；09-04 前曾实测收尾阶段挂起 20+ 分钟）"
    pkill -9 -f "xcodebuild -project swift-harness.xcodeproj" 2>/dev/null || true
    pkill -9 -f "ci-derived-data.*xctest" 2>/dev/null || true
    exit 142
  fi
  [ "$rc" -eq 0 ] || exit "$rc"
}

run_main() {
  # 09-04 源头治理：开头清旧 profraw——跨运行累积的 profraw 会被本轮 merge 污染，
  # 门禁覆盖率假高/漂移（本轮 main2 全员 100% 假高即该坑极端形态，QUALITY L165 观察项同源）。
  # 用 mv 隔离而非删除：留取证 + 规避 rm 口径。
  mkdir -p /tmp/ci-profraw-quarantine
  find .build -path '*/debug/codecov/*.profraw' -exec mv {} /tmp/ci-profraw-quarantine/ \; 2>/dev/null || true
  step "MAIN Build Release"
  swift build --configuration release
  step "MAIN Full Test Suite + Coverage"
  # 有界重试：同 PR-4（macOS 瞬态调度停滞容忍，见 QUALITY_REPORT P1）
  for attempt in 1 2; do
    perl -e 'alarm shift @ARGV; exec @ARGV' "${TEST_TIMEOUT}" swift test --parallel --enable-code-coverage && break
    pkill -f "swift-harnessPackageTests" 2>/dev/null || true   # 同上：watchdog 孤儿清理，正常失败为 no-op
    if [ "${attempt}" -eq 2 ]; then echo "❌ 全量测试两轮均失败"; exit 1; fi
    echo "⚠️ 首轮全量失败 — 有限重试一次（环境调度停滞容忍，非代码回归）"
  done
  step "MAIN Coverage 汇总（llvm-cov，后端包行覆盖）"
  BIN=.build/arm64-apple-macosx/debug/swift-harnessPackageTests.xctest/Contents/MacOS/swift-harnessPackageTests
  if [ -f "$BIN" ] && ls .build/arm64-apple-macosx/debug/codecov/*.profraw >/dev/null 2>&1; then
    # ⚠️ Apple LLVM 21（Xcode 26.6 / macOS 27 beta）bug：`llvm-profdata merge -f`
    #    任意参数序下报 “No such file or directory”（-o 输出文件）且 rc=1（已三组实验实锤）；
    #    绕过：省略 -f（覆盖已存在输出文件仍可）并将 -o 置于输入文件之后（182 个 profraw 全量验证通过）。见 QUALITY_REPORT P2
    xcrun llvm-profdata merge .build/arm64-apple-macosx/debug/codecov/*.profraw -o /tmp/ci_cov.profdata
    xcrun llvm-cov report "$BIN" -instr-profile /tmp/ci_cov.profdata \
      | grep -E '^Packages/|Filename' | sed 's/  */ /g' | awk '{print $1, $8, $9, $10}'
  else
    echo "（覆盖率数据缺失：跳过汇总，仅保留测试门禁）"
  fi
}

case "$MODE" in
  pr)    run_pr ;;
  leaks) run_leaks ;;
  xcode) run_xcode ;;
  main)  run_main ;;
  all)   run_pr; run_leaks ;;
  *)     echo "未知模式: $MODE（可选 pr|leaks|xcode|main|all）"; exit 2 ;;
esac
echo
echo "✅ 本地 CI 模拟（${MODE}）全部通过"

# 成功收尾：原子落完成标记后解除失败清理 trap（标记内容含时间与模式，供跨轮次对账）
# 09-05 增强：同日曾靠 git log --name-only 人工推断「旧 marker 对当前 HEAD 是否仍适用」——那种推断易错，
#   故把判据面指纹写进标记：复用旧 marker 前只比一项——`git rev-parse HEAD:Apps HEAD:Packages` 是否与标记内
#   swiftTree 逐字相同；不同即判据面已变更，必须重跑该门禁，禁止凭提交标题或记忆沿用（旧格式标记无该字段 ⇒ 除非另有「判据面零变更」的直接证据，否则一律按不可沿用处理）。
head_sha=$(git rev-parse --short HEAD)
swift_tree=$(git rev-parse HEAD:Apps HEAD:Packages | tr '\n' ' ' | sed 's/ $//')
dirty=$(git status --porcelain | wc -l | tr -d ' ')
printf '%s mode=%s rc=0 head=%s dirty=%s swiftTree=%s\n' "$(date '+%F %T')" "${MODE}" "$head_sha" "$dirty" "$swift_tree" > "${DONE_MARKER}.tmp" && mv -f "${DONE_MARKER}.tmp" "$DONE_MARKER"
trap - EXIT
