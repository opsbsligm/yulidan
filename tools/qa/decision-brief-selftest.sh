#!/bin/zsh
# decision-brief.py 核对门的五向变异自测（方法论同 C 层变异实测／walkthrough-ledger-sync 自测）。
# 存在理由：一个从没被变异测过的核对门，等于一个「看起来已修好」的门（QUALITY ㊳-1）。
# 全程在 mktemp 沙箱副本里做变异，绝不改真仓文件。rc: 0 全过 / 1 有用例失败 / 2 环境缺项。
set -u
REPO="${PWD}"
SB="$(mktemp -d /tmp/dbrief-selftest.XXXXXX)"
fails=0
expect() { # expect <用例> <期望rc> <实际rc> <备注>
  if [ "$2" = "$3" ]; then print -r -- "✅ ${1}｜rc=${3}"
  else print -r -- "❌ ${1}｜rc=${3} 期望 ${2} ${4:-}"; fails=$((fails + 1)); fi
}
fresh() { # 重置沙箱为「源表＋已 emit 的 brief＋两个工具」的干净态
  rm -rf "${SB}/x" 2>/dev/null
  mkdir -p "${SB}/x/docs" "${SB}/x/tools/qa"
  cp "${REPO}/docs/DECISION_INDEX.md" "${SB}/x/docs/"
  cp "${REPO}/tools/qa/decision-brief.py" "${REPO}/tools/qa/decision-pending.sh" "${SB}/x/tools/qa/"
  ( cd "${SB}/x" && python3 tools/qa/decision-brief.py --emit >/dev/null )
}
[ -f "${REPO}/tools/qa/decision-brief.py" ] || { print -r -- "❌ 缺被测工具" >&2; exit 2; }

# T0 基线：干净态必须 rc=0（否则后面全是假阳性）
fresh; ( cd "${SB}/x" && python3 tools/qa/decision-brief.py --check >/dev/null 2>&1 ); expect "T0 干净态须一致" 0 "$?"

# T1 手改 brief 状态 ⇒ 必须报状态漂移（副本漂移是铁律 3 的硬违反）
fresh
# ⚠️ 变异必须打在**数据行的状态列**上：首版用 `sed '3s/☐/✅/'` 打到了第 3 行的引用块（那里没有 ☐），
#    变异根本没生效却把用例判成「checker 有洞」——变异注入不精确会伪造缺陷，与 ㊹-3 同族。
python3 - "${SB}/x/docs/DECISION_BRIEF.md" <<'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
hit = 0
for i, line in enumerate(lines):
    if line.startswith("| ") and line.count("|") >= 6:
        cells = line.strip().strip("|").split("|")
        if "☐" in cells[-1]:
            cells[-1] = cells[-1].replace("☐", "✅")
            lines[i] = "|" + "|".join(cells) + "|"
            hit += 1
            break
assert hit == 1, f"变异未生效（数据行里没找到 ☐）→ hit={hit}"
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
[ "$?" = "0" ] || { print -r -- "❌ T1 变异注入失败（自测自身的注入必须自证生效）"; fails=$((fails + 1)); }
( cd "${SB}/x" && python3 tools/qa/decision-brief.py --check >/tmp/db-t1.log 2>&1 ); expect "T1 手改 brief 状态须报漂移" 1 "$?" "$(grep -c '状态漂移' /tmp/db-t1.log) 条"

# T2 删 brief 一行 ⇒ 必须报缺项（防「手册/速览漏项」复发）
fresh; sed -i '' '/^| \*\*D-3\*\*/d;/^| D-3 /d' "${SB}/x/docs/DECISION_BRIEF.md"
grep -q '| D-3 ' "${SB}/x/docs/DECISION_BRIEF.md" && sed -i '' '/^| D-3 /d' "${SB}/x/docs/DECISION_BRIEF.md"
( cd "${SB}/x" && python3 tools/qa/decision-brief.py --check >/tmp/db-t2.log 2>&1 ); expect "T2 速览缺项须报" 1 "$?" "$(grep -c '缺项' /tmp/db-t2.log) 条"

# T3 塞幽灵 ID ⇒ 必须报幽灵
fresh; printf '%s\n' '| D-99 | 幽灵项 | 🟢 不需 | 源表未标注（不代你猜） | ☐ |' >> "${SB}/x/docs/DECISION_BRIEF.md"
( cd "${SB}/x" && python3 tools/qa/decision-brief.py --check >/tmp/db-t3.log 2>&1 ); expect "T3 幽灵项须报" 1 "$?" "$(grep -c '幽灵' /tmp/db-t3.log) 条"

# T4 源表新增 ☐ 而未重新 emit ⇒ 必须双向报（缺项 ＋ 与权威口径差）
fresh; printf '%s\n' '| **D-98** | 源表新增待拍板项 | (a) 甲 | ☐ | 自测注入 |' >> "${SB}/x/docs/DECISION_INDEX.md"
( cd "${SB}/x" && python3 tools/qa/decision-brief.py --check >/tmp/db-t4.log 2>&1 ); expect "T4 源表新增未同步须报" 1 "$?" "$(grep -cE '缺项|与权威口径不一致' /tmp/db-t4.log) 条"

# T5 源表不可读 ⇒ rc=3（核对无效绝不等于通过）
fresh; rm -f "${SB}/x/docs/DECISION_INDEX.md"
( cd "${SB}/x" && python3 tools/qa/decision-brief.py --check >/dev/null 2>&1 ); expect "T5 源表不可读须 rc=3" 3 "$?"

print -r -- "=== decision-brief 自测：失败=${fails}｜沙箱 ${SB} ==="
[ "$fails" -eq 0 ] || exit 1
exit 0
