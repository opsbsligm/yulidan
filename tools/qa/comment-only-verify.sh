#!/usr/bin/env bash
# 「本次改动仅注释行」机械证明器（09-05）。
# 存在理由：QUALITY 里要用「注释改动不改逻辑」论证四门禁能否沿用——这句话此前只能靠人眼看 diff。
# 本工具把它变成退出码：diff 中每一条新增/删除行，strip 后必须以 // 或 /// 开头（或为纯空行），
# 否则判为含逻辑行 ⇒ rc=1（门禁沿用论证不成立，必须重跑全量门禁）。
# 用法: tools/qa/comment-only-verify.sh [git diff 的额外参数，默认取工作区未提交改动]
#   例: tools/qa/comment-only-verify.sh --cached
#       tools/qa/comment-only-verify.sh HEAD~1 HEAD
set -uo pipefail
DIFF=(git diff --no-color --unified=0 -- "$@")
if [ $# -eq 0 ]; then DIFF=(git diff --no-color --unified=0); fi
out="$("${DIFF[@]}")" || { echo "git diff 失败"; exit 2; }
if [ -z "$out" ]; then echo "diff 为空 ⇒ 无可证内容"; exit 0; fi
python3 - "$out" <<'PY'
import re, sys
txt = sys.argv[1]
cur = None
viol = []
n_add = n_del = n_hunk = 0
for line in txt.splitlines():
    if line.startswith("+++ b/"):
        cur = line[6:]
        continue
    if line.startswith("@@"):
        n_hunk += 1
        continue
    if line.startswith("+") and not line.startswith("+++"):
        body = line[1:].strip()
        n_add += 1
        ok = (body == "" or body.startswith("//"))
        if not ok:
            viol.append((cur, "+", body[:120]))
    elif line.startswith("-") and not line.startswith("---"):
        body = line[1:].strip()
        n_del += 1
        ok = (body == "" or body.startswith("//"))
        if not ok:
            viol.append((cur, "-", body[:120]))
print(f"扫描：hunk {n_hunk}，新增行 {n_add}，删除行 {n_del}")
for f, sign, b in viol:
    print(f"NONCOMMENT {f} [{sign}] {b}")
print(f"—— 非注释行 {len(viol)} 条")
if viol:
    print("⇒ 含逻辑改动：四门禁沿用论证不成立，须跑全量门禁（pr/main/xcode/leaks）。")
    sys.exit(1)
print("⇒ 全部改动仅注释行（含空行）：逻辑字节零变更；沿用论证的「代码面等价」前提成立。")
PY
