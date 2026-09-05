#!/usr/bin/env bash
# 待拍板计数的唯一权威来源＝DECISION_INDEX 表格里「状态列」为 ☐ 的 D 项。
# 存在理由：本仓已两次把拍板池数量写错（9→8／列了 11 个符号却写 9），故计数一律现算现写。
# 退出码恒 0（这是查询工具，不是守卫）；输出末行为「待拍板 N 项」。
set -euo pipefail
DOC="${1:-docs/DECISION_INDEX.md}"
python3 - "$DOC" <<'PY'
import io, sys
pend, done, half = [], [], []
for l in io.open(sys.argv[1], encoding="utf-8"):
    s = l.strip()
    if not s.startswith("| **D-"):
        continue
    cells = [c.strip() for c in s[1:-1].replace("\\|", "\0").split("|")]
    name = cells[0].replace("**", "")
    state = next((c for c in cells[1:] if c.startswith(("☐", "✅", "◐"))), "")
    (pend if state.startswith("☐") else half if state.startswith("◐") else done).append(name)
print("待拍板（☐）: " + ", ".join(pend))
print("半结（◐，残余待目检）: " + (", ".join(half) or "—"))
print("已闭环（✅）: " + ", ".join(done))
print(f"待拍板 {len(pend)} 项")
PY
