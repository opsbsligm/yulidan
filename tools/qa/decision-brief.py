#!/usr/bin/env python3
"""从决策总账机器派生「待拍板速览」，并与既有权威计数工具交叉核对（**不是手抄副本**）。

存在理由：DoD 要求「D-1~D-6 拍板记录齐」，而总账单格动辄数千字（D-1 格含 6 段注记）——
材料厚重本身就是拍板瓶颈，G2/G3 都卡在这。本工具只输出**可机器判定**的信息：
ID／议题／**需不需要你亲自参与**（该行文本含「目检」＝需；否则＝纯静默可执行）／状态。
「建议」列只在源表**已显式标注**时原样截取，未标注就如实留白——不发明推荐，也不替历史记忆背书。

口径纪律（09-06 教训）：判据与 `tools/qa/decision-pending.sh` **完全复用**（状态＝状态列首个
以 ☐/✅/◐ 开头的单元格；☐ 为待拍板，◐ 为半结），并额外**交叉核对该工具输出的 ID 集合**——
⇒ 若两处对「还剩几项」口径不一，本工具直接 rc=1，不允许出现第二套账（PR-0.5 的副本漂移教训）。

用法：decision-brief.py --emit   生成 docs/DECISION_BRIEF.md
      decision-brief.py --check  核对 brief 与源表/权威计数一致（rc=1 漂移）
rc: 0 一致 / 1 漂移 / 3 源不可读或表结构异常（核对无效绝不等于通过）
"""
import os
import re
import subprocess
import sys

SRC = "docs/DECISION_INDEX.md"
DST = "docs/DECISION_BRIEF.md"
PENDING = "tools/qa/decision-pending.sh"
MARKS = ("☐", "✅", "◐")
# 「需你参与」的宽口径关键词：判据是关键词命中而非语义理解 ⇒ 取向为**宁多报不漏报**
# （把要你动手的事标成可静默，比反过来更有害）。列名措辞也据此保守化，见 render()。
NEED_KEYS = ("目检", "实机", "手动", "择时", "你确认", "用户拍板", "你拍板", "你目检")


def parse(path):
    """判据与 decision-pending.sh 逐字一致：仅 `| **` 行，状态取首个 ☐/✅/◐ 起始单元格。"""
    if not os.path.isfile(path):
        print(f"源文件不存在：{path}", file=sys.stderr)
        sys.exit(3)
    rows = []
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if not s.startswith("| **"):
            continue
        cells = [c.strip() for c in s[1:-1].replace("\\|", "\0").split("|")]
        name = cells[0].replace("**", "")
        state = next((c for c in cells[1:] if c.startswith(MARKS)), "")
        if not state:
            continue
        topic = re.sub(r"\*\*", "", cells[1])
        body = " ".join(cells[2:])
        rows.append({"id": name, "topic": topic, "state": state,
                     "needs_user": any(k in body for k in NEED_KEYS),
                     "rec": next((c for c in (re.findall(r"\*\*[^*]*新·推荐[^*]*\*\*", body)
                                              + re.findall(r"Agent 推荐[^|]{0,60}", body)) if c), "")})
    if not rows:
        print("❌ 未识别到任何 `| **ID**` 行 ⇒ 表结构异常，拒绝报 0 项", file=sys.stderr)
        sys.exit(3)
    return rows


def authoritative():
    """权威集合＝decision-pending.sh 现算结果（读不到即 rc=3，绝不静默当空集）。"""
    if not os.path.isfile(PENDING):
        print(f"❌ 权威计数工具不存在：{PENDING}", file=sys.stderr)
        sys.exit(3)
    r = subprocess.run(["bash", PENDING], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"❌ 权威计数工具 rc={r.returncode}：{r.stderr.strip()[:200]}", file=sys.stderr)
        sys.exit(3)
    out, ids = {}, []
    for line in r.stdout.splitlines():
        m = re.match(r"(待拍板 D 段|待拍板 非 D 段|半结)（[^）]*）: (.*)", line)
        if m and m.group(2) != "—":
            ids += [x.strip() for x in m.group(2).split(",")]
            out[m.group(1)] = [x.strip() for x in m.group(2).split(",")]
    return set(ids), out


def render(rows):
    pend = [r for r in rows if r["state"].startswith("☐")]
    half = [r for r in rows if r["state"].startswith("◐")]
    silent = sum(1 for r in pend + half if not r["needs_user"])
    L = [
        "# 待拍板速览（机器派生，**禁止手改**）",
        "",
        "> 源＝`docs/DECISION_INDEX.md`（唯一权威账本）；本文件由 `python3 tools/qa/decision-brief.py --emit`",
        "> 生成，一致性由门禁 **PR-0.7** 核对（漂移即红，且与 `decision-pending.sh` 的集合互为交叉校验）。",
        "> 要改内容：改源表 → 重新 `--emit`；手改本文件必被门禁拦下。",
        ">",
        "> **与 G3 手册 §4 的分工**（两者用途不同，不构成重复账本）：本表服务于「**现在怎么拍**」——",
        "> 只列未闭环项、并标出哪些**未见需你参与的表述**（可静默执行）；手册 §4 服务于「**走查时逐项确认**」，",
        "> 含已闭环项。两者各由 PR-0.7／PR-0.5 独立核对，均不得手改其中派生的那一份。",
        "",
        f"> **待拍板 ☐ {len(pend)} 项 ＋ 半结 ◐ {len(half)} 项**。其中 🟢 **未见需你参与的表述** "
        f"**{silent} 项**（可静默执行），⏱ **需你参与** **{len(pend)+len(half)-silent} 项**；",
        f"判据为宽口径关键词（{len(NEED_KEYS)} 个），详见文末口径说明。",
        "",
        "| ID | 议题 | 需你参与？ | 源表已标注的建议 | 状态 |",
        "|----|------|-----------|------------------|------|",
    ]
    for r in pend + half:
        topic = r["topic"] if len(r["topic"]) <= 46 else r["topic"][:46] + "…"
        rec = re.sub(r"\*\*", "", r["rec"]).strip() or "源表未标注（不代你猜）"
        if len(rec) > 68:
            rec = rec[:68] + "…"
        L.append(f"| {r['id']} | {topic} | {'⏱ 需你参与' if r['needs_user'] else '🟢 未见需你参与的表述'} "
                 f"| {rec} | {r['state']} |")
    L += ["",
          "**判据口径（可核）**：状态取状态列首个以 `☐`/`✅`/`◐` 起始的单元格（与 `decision-pending.sh` 同判据）；",
          "「需你参与」判据＝该行文本命中关键词之一：" + "、".join(f"`{k}`" for k in NEED_KEYS) + "；",
          "⚠️ **这是关键词判据不是语义理解**，漏报方向为「把需要你参与的事项标成 🟢」⇒ 已刻意取宽口径（宁多报），",
          "但**不保证 100% 识别**：真要拍某项，请以源表该格全文为准，本表只负责让你**先挑出该花时间的项**。",
          "「建议」列仅原样截取源表显式标注（`新·推荐`／`Agent 推荐…`），未标注即留白——本工具不发明推荐。",
          "本工具不发明推荐、不引申判断、不把「读不到」当成「没有」。", ""]
    return "\n".join(L)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--check"
    rows = parse(SRC)
    if mode == "--emit":
        open(DST, "w", encoding="utf-8").write(render(rows))
        print(f"已生成 {DST}（源表 ID 行 {len(rows)}）")
        return 0
    if not os.path.isfile(DST):
        print(f"❌ {DST} 不存在 ⇒ 无法核对（不等于通过）", file=sys.stderr)
        return 3
    mine = {r["id"]: r["state"] for r in rows if r["state"].startswith(("☐", "◐"))}
    auth_ids, _ = authoritative()
    text = open(DST, encoding="utf-8").read()
    # ⚠️ ID 集合必须兼容中文/非 ASCII ID（轴2、RSS 可见态组），且必须跳过表头与分隔行——
    #    首版用 [A-Z0-9-]{2,} 正则把这两个真项误报成「缺项」、把表头 `ID`／分隔 `----` 误报成「幽灵」
    #    （同 QUALITY ㊶-1 的教训：核对器的 ID 兼容性不足会双向造假）。故改为按列切分并显式排除表头。
    inbrief = {}
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 5:
            continue
        ident = cells[0]
        if ident in ("ID", "议题") or not ident or set(ident) <= set("-: "):
            continue                      # 表头行／分隔行
        if cells[1].startswith("议题"):
            continue
        inbrief[ident] = cells[4]
    miss = sorted(set(mine) - set(inbrief))
    ghost = sorted(set(inbrief) - set(mine))
    drift = sorted(k for k in set(mine) & set(inbrief) if mine[k] != inbrief[k])
    auth_gap = sorted(set(mine) ^ auth_ids)
    for k in miss:
        print(f"❌ 速览缺项：{k}")
    for k in ghost:
        print(f"❌ 速览幽灵（源表已闭环或不存在的 ID）：{k}")
    for k in drift:
        print(f"❌ 状态漂移：{k} 源表「{mine[k]}」vs 速览「{inbrief[k]}」")
    for k in auth_gap:
        print(f"❌ 与权威计数口径不一致：{k}")
    print(f"decision-brief：未闭环 {len(mine)}｜速览 {len(inbrief)}｜缺项 {len(miss)} 幽灵 {len(ghost)} "
          f"漂移 {len(drift)}｜与权威口径差 {len(auth_gap)}")
    return 1 if (miss or ghost or drift or auth_gap) else 0


sys.exit(main())
