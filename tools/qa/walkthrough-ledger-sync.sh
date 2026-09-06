#!/usr/bin/env bash
# walkthrough-ledger-sync.sh —— 走查手册 §4 速览副本 vs 权威总账 DECISION_INDEX 的一致性核对。
#
# 存在理由（09-06 实测两处事故）：手册 §4 是手抄副本，实测发现①状态过时（D-13 总账已 ✅ 而副本仍 ☐）
# 与②整项缺失（D-14/D-15/D-19/D-22/D-25/RSS 六项待拍板未进副本）。DoD 明写「G3 开始前须全部有记录」
# ⇒ 副本缺项会让用户按手册走查时漏拍板。凡是「手工维护的副本」都必须有一道可重复跑的核对门。
#
# 关键教训固化：ID 匹配必须接受 `| D-x |`、`| **D-x** |`、`| A14 |`、`| G1-SCOPE |` 多种写法。
# 09-06 我第一版只匹配 `| **` 开头，于是把 9 条已在册的待拍板判成「副本未列」——
# 与当日 #7「按修饰符字面量搜索推出无覆盖」是同一族假阴性（QUALITY ㉘）。
#
# 用法：tools/qa/walkthrough-ledger-sync.sh [总账.md] [手册.md]
# 退出码：0 一致 / 1 存在漂移或缺项 / 3 文件不可读（响亮失败，不得伪装「已核对通过」）
set -uo pipefail
LEDGER="${1:-docs/DECISION_INDEX.md}"
WALK="${2:-docs/G3_MVP_WALKTHROUGH.md}"
python3 - "$LEDGER" "$WALK" <<'PY'
import io, re, sys

ledger_path, walk_path = sys.argv[1], sys.argv[2]


def read(path):
    try:
        return io.open(path, encoding="utf-8").read().split("\n")
    except OSError as e:
        print(f"FATAL 文件不可读：{path}（{e}）⇒ 核对无效，禁止据此判定「已一致」")
        sys.exit(3)


ID_RE = re.compile(r"^\|\s*\**([A-Za-z0-9一-鿿][^|*]*?)\**\s*\|")


def norm(x):
    return x.strip().strip("*").strip()


def ledger_rows(lines):
    """总账：ID → 状态列（含 ✅/☐/◐）。只认表内加粗 ID 行。"""
    out = {}
    for l in lines:
        if not l.startswith("| **"):
            continue
        c = [x.strip() for x in l.strip().strip("|").split("|")]
        if len(c) < 4:
            continue
        m = re.match(r"^\*\*(.+?)\*\*", c[0])
        if m:
            out[m.group(1).strip()] = c[3]
    return out


def walk_rows(lines):
    """手册 §4：ID → 拍板列。ID 列的多种写法都接受（见文件头教训）。"""
    out, in_sec = {}, False
    for l in lines:
        if l.startswith("## 4."):
            in_sec = True
            continue
        if in_sec and l.startswith("## "):
            break
        if not in_sec or not l.startswith("|"):
            continue
        c = [x.strip() for x in l.strip().strip("|").split("|")]
        if len(c) < 4:
            continue
        key = norm(c[0])
        if key in ("ID", "") or set(key) <= set("-: "):
            continue
        out[key] = c[-1]
    return out


L, W = ledger_rows(read(ledger_path)), walk_rows(read(walk_path))
pending = [k for k, st in L.items() if st.startswith("☐")]
drift = [k for k, v in W.items()
         if k in L and v.startswith("☐") and "✅" in L[k]]
missing = [k for k in pending if k not in W]
ghost = [k for k in W if k not in L]

print(f"总账条目={len(L)}（其中待拍板 {len(pending)}）｜手册 §4 条目={len(W)}")
for name, xs in (("状态漂移（手册仍 ☐ 而总账已 ✅）", drift),
                 ("总账待拍板但手册 §4 未列", missing),
                 ("手册 §4 有而总账无此 ID", ghost)):
    print(f"{'❌' if xs else '✅'} {name}：{len(xs)} {xs if xs else ''}")
sys.exit(1 if (drift or missing or ghost) else 0)
PY
