#!/usr/bin/env bash
# 待拍板计数的唯一权威来源＝DECISION_INDEX 表格「状态列」为 ☐ 的**全部行**。
# 存在理由：本仓已两次把拍板池数量写错（9→8／列了 11 个符号却写 9），故计数一律现算现写。
# 09-05 纠偏：本工具旧版只匹配 `^\| **D-`，而总账同一张表里还有 A14／轴2／RSS 可见态组三个
# ☐ 项被漏计 ⇒ 对外报「10 项」而用户实际要拍的是 13 项。现同时输出 D 段与非 D 段，末行给合计。
# 退出码恒 0（这是查询工具，不是守卫）；非零仅出现在文件缺失/表结构异常（防「读不到＝读成 0」）。
set -euo pipefail
DOC="${1:-docs/DECISION_INDEX.md}"
[ -f "$DOC" ] || { echo "❌ 总账文件不存在：${DOC}（拒绝把读不到读成 0 项）" >&2; exit 2; }
python3 - "$DOC" <<'PY'
import io, sys
rows = 0
pend_d, pend_x, done, half = [], [], [], []
for l in io.open(sys.argv[1], encoding="utf-8"):
    s = l.strip()
    if not s.startswith("| **"):
        continue
    rows += 1
    cells = [c.strip() for c in s[1:-1].replace("\\|", "\0").split("|")]
    name = cells[0].replace("**", "")
    state = next((c for c in cells[1:] if c.startswith(("☐", "✅", "◐"))), "")
    if not state:
        continue
    if state.startswith("☐"):
        (pend_d if name.startswith("D-") else pend_x).append(name)
    elif state.startswith("◐"):
        half.append(name)
    else:
        done.append(name)
if rows == 0:
    print("❌ 表内未识别到任何 `| **ID**` 行 ⇒ 结构异常，拒绝报 0 项", file=sys.stderr)
    sys.exit(2)
print("待拍板 D 段（☐）: " + (", ".join(pend_d) or "—"))
print("待拍板 非 D 段（☐）: " + (", ".join(pend_x) or "—"))
print("半结（◐，残余待目检）: " + (", ".join(half) or "—"))
print("已闭环（✅）: " + (", ".join(done) or "—"))
tot = len(pend_d) + len(pend_x)
print(f"表内 ID 行总数 {rows}；待拍板合计 {tot} 项（D 段 {len(pend_d)} ＋ 非 D 段 {len(pend_x)}）")
PY
