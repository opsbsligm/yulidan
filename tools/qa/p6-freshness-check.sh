#!/bin/bash
# G3 §0 P6「走查构建新鲜度」三件判据（机械化；A 层只读，零可见状态变化）
# 存在理由：原单条 mtime 判据（bundle mtime ≥ HEAD 提交时间）在 docs-only 链上会**假阴性**
# ——文档提交不改二进制，却把 HEAD 提交时间推后，于是每次提交后都得重新 sync 才能"过字面"。
set -uo pipefail
cd "$(dirname "$0")/../.."
BIN=".build/arm64-apple-macosx/debug/HarnessApp.app/Contents/MacOS/HarnessApp"
[ -f "$BIN" ] || { echo "❌ bundle 二进制不存在"; exit 1; }

rc=0
# (a) bundle 二进制 == 当前构建产物（脚本内含 pre-sign sha 断言＋同步戳）
if zsh tools/rebuild-app.sh verify >/tmp/p6_verify.log 2>&1; then
  echo "✅ (a) verify rc=0：$(tail -1 /tmp/p6_verify.log)"
else
  echo "❌ (a) verify 失败：$(tail -1 /tmp/p6_verify.log)"; rc=1
fi

# (b) HEAD 代码面指纹 == 四门禁 marker 的 swiftTree（判据面与走查对象同一）
mark_head=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^head=/){sub("head=","",$i); print $i; exit}}' /tmp/ci.done.all)
mark_tree=$(sed -n 's/.*swiftTree=//p' /tmp/ci.done.all | tr -s ' ')
head_tree=$(git rev-parse HEAD:Apps HEAD:Packages | tr '\n' ' ' | sed 's/ $//')
[ -z "$mark_head" ] && { echo "❌ (b) 读不到 marker"; rc=1; }
if [ -n "$mark_head" ] && [ "$head_tree" = "$mark_tree" ]; then
  apps="${head_tree%% *}"; pkgs="${head_tree##* }"
  echo "✅ (b) 代码面指纹与 marker@${mark_head} 逐字相同：Apps=${apps:0:12}…／Packages=${pkgs:0:12}…"
else
  echo "❌ (b) 代码面与门禁判据面不同 ⇒ 必须重跑门禁"; rc=1
fi

# (c) 二进制不早于「最近一次改代码面的提交」（不与 docs-only 提交比）
code_ct=$(git log -1 --format=%ct -- Apps Packages)
bin_mt=$(stat -f %m "$BIN")
if [ "$bin_mt" -ge "$code_ct" ]; then
  echo "✅ (c) bundle mtime=${bin_mt} ≥ 代码面提交时间=${code_ct}"
else
  echo "❌ (c) bundle 早于代码面提交 ⇒ 需 sync"; rc=1
fi
exit $rc
