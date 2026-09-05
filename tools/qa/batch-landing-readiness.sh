#!/usr/bin/env bash
# 注释批次「落批就绪」检查器（09-05）。**只判定、只报告，绝不提交、绝不启动 App、绝不触碰键鼠**。
# 存在理由：§21.2 注释批次要在 idle≥60min 且门禁通过后才落地，此前这条判据只写在报告里靠人记；
# 把它变成退出码，任何后续轮次（含 heartbeat）都能一眼判断「现在到底能不能跑重门禁」。
#
# 退出码：0 就绪 / 3 空闲不足 / 4 含逻辑行（沿用论证不成立）/ 5 断言门未过 / 6 轻门禁未过 / 7 工作区改动面异常
set -uo pipefail
cd "$(dirname "$0")/../.."   # 本工具在 tools/qa/ 下＝上跳两级（照抄 ci-local.sh 的单级会停在 tools/）
IDLE_MIN_REQUIRED="${IDLE_MIN_REQUIRED:-60}"

dirty_swift=$(git status --porcelain | awk '$1=="M" && $2 ~ /\.swift$/ {print $2}')
if [ -z "$dirty_swift" ]; then echo "工作区无 .swift 改动 ⇒ 无批次待落（本工具不适用）"; exit 7; fi
echo "待落批次文件："
echo "$dirty_swift" | sed 's/^/  /'
bad=$(echo "$dirty_swift" | grep -vc '^Apps/' || true)
if [ "${bad:-0}" != "0" ]; then echo "❌ 批次含 Apps/ 之外或非注释预期外的 .swift ⇒ 请人工确认改动面"; exit 7; fi

idle_s=$(python3 -c "
import subprocess,re
o=subprocess.run(['ioreg','-c','IOHIDSystem'],capture_output=True,text=True).stdout
m=re.search(r'\"HIDIdleTime\" = (\d+)',o)
print(int(int(m.group(1))/1e9))")
echo "HIDIdleTime = ${idle_s}s（阈值 $((IDLE_MIN_REQUIRED*60))s）"
if [ "$idle_s" -lt $((IDLE_MIN_REQUIRED*60)) ]; then
  echo "⇒ 未就绪：你在用电脑（铁律 8）。本工具不会去跑重门禁，也不会提交。"
  exit 3
fi

# 注意（本仓已登记过的坑）：`cmd | tail` 之后取 $? 拿到的是 tail 的码 ⇒ 先落文件再取码，避免假绿。
echo "--- 判据 1：仅注释行 ---"
# 必须限定到批次路径：校验器默认扫整个工作区 diff，若同期还有 tools/ 等未提交改动会混入并误报非注释行（实测踩到）。
bash tools/qa/comment-only-verify.sh -- Apps >/tmp/bqa_cmt.out 2>&1; rc_cmt=$?
tail -2 /tmp/bqa_cmt.out
[ "$rc_cmt" -eq 0 ] || { echo "⇒ 含逻辑行：沿用论证不成立（rc=${rc_cmt}）"; exit 4; }
echo "--- 判据 2：断言门 ---"
python3 tools/qa/official-claim-lint.py --root . >/tmp/bqa_claim.out 2>&1; rc_claim=$?
tail -2 /tmp/bqa_claim.out
[ "$rc_claim" -eq 0 ] || { echo "⇒ 断言门 rc=${rc_claim}"; exit 5; }
echo "--- 判据 3：轻门禁（lint / format / parse）---"
swiftlint lint --quiet --strict >/tmp/bqa_lint.out 2>&1; rl=$?
swiftformat --lint . >/tmp/bqa_fmt.out 2>&1; rf=$?
rp=0
for f in $dirty_swift; do xcrun swiftc -parse "$f" >/dev/null 2>&1 || rp=1; done
echo "swiftlint rc=$rl  swiftformat rc=$rf  parse rc=$rp"
if [ "$rl" != "0" ] || [ "$rf" != "0" ] || [ "$rp" != "0" ]; then echo "⇒ 轻门禁未过"; exit 6; fi

cat <<'NEXT'
⇒ 就绪。idle 到位后按此序执行（重门禁＝需你知情；本工具不代为提交）：
   1) bash tools/ci-local.sh pr            # Apps 子树指纹已变 ⇒ pr 必须真跑，不得沿用
   2) git add <逐条列出上述 4 个文件>       # ❌禁 git add -A
   3) git commit -m "docs(glass): §21.2 注释批次 …"   # message 每条「已…」须能在 diff 里指认
   4) bash tools/ci-local.sh main && bash tools/ci-local.sh xcode && bash tools/ci-local.sh leaks
      # main/xcode/leaks 可否沿用＝D-? 由你裁；本工具不默认沿用
   5) git push --mirror /Users/liguangming/code/swift-harness-backup.git 后 ls-remote 验 MATCH
NEXT
