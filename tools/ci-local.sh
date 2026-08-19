#!/bin/bash
# 本地 CI 模拟（与 .github/workflows/swift-ci.yml 各 job 对齐；GitHub 远端未启用期间使用）
# 用法: tools/ci-local.sh [pr|leaks|xcode|main|all]   默认 pr
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-pr}"

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
  swift test
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
  swift test --parallel --enable-code-coverage
  step "MAIN Coverage 汇总（llvm-cov，后端包行覆盖）"
  BIN=.build/arm64-apple-macosx/release/swift-harnessPackageTests.xctest/Contents/MacOS/swift-harnessPackageTests
  if [ -f "$BIN" ] && ls .build/arm64-apple-macosx/release/codecov/*.profraw >/dev/null 2>&1; then
    xcrun llvm-profdata merge -f -o /tmp/ci_cov.profdata .build/arm64-apple-macosx/release/codecov/*.profraw
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
