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

step() { echo; echo "===== $1 ====="; }

run_pr() {
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
  step "LEAKS leaks --atExit MemProbe 500（期望 0 leaks）"
  leaks --atExit -- .build/debug/MemProbe 500
}

run_xcode() {
  step "XCODE Generate project"
  xcodegen generate
  step "XCODE Build (HarnessApp Debug)"
  xcodebuild -project swift-harness.xcodeproj -scheme HarnessApp -configuration Debug \
    -derivedDataPath ./ci-derived-data build
  step "XCODE Test (HarnessApp Debug)"
  xcodebuild -project swift-harness.xcodeproj -scheme HarnessApp -configuration Debug \
    -derivedDataPath ./ci-derived-data test
}

run_main() {
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
printf '%s mode=%s rc=0\n' "$(date '+%F %T')" "${MODE}" > "${DONE_MARKER}.tmp" && mv -f "${DONE_MARKER}.tmp" "$DONE_MARKER"
trap - EXIT
