#!/usr/bin/env python3
# 代码注释「官方」引用审计门（09-05，BENCHMARK §21 一次性人工审计 → 可复跑退出码）。
# 存在理由：§18.5 真实发生过「注释写官方、实际无原文」的过度归属。人工审计会随代码演进失效，
# 故把 §21.1 三档判定做成机器可判的两条硬规则：
#   R1 正断言（含「官方」）：必须挂锚点（§号／docs/*.md／BENCHMARK／swiftdoc／SDK／HIG／apple.com）
#      或带行内逐字英文原文，或明示我方属性（我方/推论/推断/预测/未实测/保守/…）；
#   R2 负断言（官方无/官方没有/官方不存在）：额外必须挂「检索门」锚点（§20/§21.3/swiftdoc/在线）。
# 锚点取证窗口＝断言行同行±1（实测：整块取证会集体洗白，见 anchor_window 文档串）。
# 仅「玻璃类源码」为审计主体（§21 口径）；LLM/提供商语境与测试代码只报数量做口径闭合校验。
#
# 用法: python3 tools/qa/official-claim-lint.py [--root DIR] [--expect 29,15,10] [--all]
# 退出码: 0=玻璃类断言全部有锚/自证; 1=存在无锚断言或负断言未走门; 2=口径不闭合(总数!=三分和)。
import argparse
import io
import os
import re
import sys

ANCHOR = re.compile(
    r"§\s*\d|§\s*[〇一二三四五六七八九十]+|BENCHMARK|swiftdoc|\.swiftdoc|swiftinterface"
    r"|SDK|HIG|apple\.com|tutorials/data|docs/[\w\-./]+\.md"
)
# 行内逐字英文引文本身即原文证据，等价于锚点。必须是英文散文形态：
# ≥25 字符 且 ≥4 个词——否则 Swift 字符串字面量（如 "harness-sidebar-selection"）会冒充引文（实测踩到）。
QUOTE_CHARS = set(
    r"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ,;:/()._\-?=%+!*#>"
)

def quote_regions(lines):
    """返回若干「逐字引文区间」(首行, 末行)，用于承认跨行折行的官方原文。

    严格性来自三条同时成立才算数（每条都有实测反例）：
      1) 引号必须在**注释行内**配对 ⇒ 排除 Swift 字符串字面量冒充引文
         （实测踩到 static let selectionID = "harness-sidebar-selection" 把 :133 洗白）；
      2) 区间不得跨越非注释行 ⇒ 排除「注释引文 + 下方代码行」拼接成假区间；
      3) 区间内容须 ≥4 个空格分词 ⇒ 排除短标识符。
    """
    regions = []
    open_line = None
    for i, l in enumerate(lines):
        is_comment = l.strip().startswith("//")
        if not is_comment:
            open_line = None  # 规则 2：代码行切断引文区间
            continue
        for ch in l:
            if ch == '"':
                if open_line is None:
                    open_line = i
                else:
                    body = "".join(
                        lines[j] for j in range(open_line, i + 1)
                    ).replace('"', " ")
                    words = [w for w in body.split() if any(c.isalpha() for c in w)]
                    if i > open_line or len(words) >= 4:
                        if len(words) >= 4:
                            regions.append((open_line, i))
                    open_line = None
    return regions
SELF = re.compile(r"我方|推论|推导|推断|预测|未实测|待实测|保守|策略|实测|实证|非官方|假设")
NEG = re.compile(r"官方(无|没有|不存在|未提及|不含|未描述|未规定)|无官方|没有官方|官方未")
NEG_GATE = re.compile(r"§\s*20|§\s*21\.3|swiftdoc|在线|swiftinterface")
# 跨领域语境（提供商「官方」，§21.4）：这类断言不属 Apple 断言面，改由提供商文档核验（§21.6 已跑首轮）。
PROVIDER = re.compile(r"Ollama|DeepSeek|OpenAI|Claude|Gemini|API 地址|baseURL|reasoning_effort|思考模型|端点|默认地址|qwen|/api/")
APPLE = re.compile(r"Glass|glassEffect|glassEffectTransition|GlassEffectContainer|morph|materialize|union|spacing|透窗|HIG|SDK|swiftdoc|SwiftUI|matchedGeometry|section|toolbar|buttonBorderShape|Menu|WindowGroup|MenuBarExtra|Form|\bWindow\b")

def is_glass(rel):
    p = "/" + rel
    return ("/Sources/Styles/" in p or "/Sources/Views/" in p
            or rel.endswith("Sources/HarnessApp.swift"))

def is_llm(rel):
    p = "/" + rel
    return rel.startswith("Packages/") or "/ViewModels/" in p or rel.endswith("LLMConfigStore.swift")

def is_test(rel):
    return "/Tests/" in ("/" + rel) or rel.endswith("Tests.swift")

def anchor_window(lines, idx, span=1):
    """锚点/自证的取证窗口＝断言行本身 ± span 行（默认 ±1）。

    取证依据（实测，勿改回整块）：整块取证会因块内任意一行的弱自证词
    （如中性的「正确构造」）把同一块内所有「官方」断言集体洗白——
    HEAD 快照上 BENCHMARK §21.2 的 11 条里漏检 6 条，成因即此。
    """
    a = max(0, idx - span)
    b = min(len(lines) - 1, idx + span)
    return "".join(lines[a:b + 1])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="扫描根（默认当前目录；比对 HEAD 时指向 git archive 解出目录）")
    ap.add_argument("--expect", default="", help="期望三分计数 玻璃,LLM,测试（不匹配即口径不闭合 rc=2）")
    ap.add_argument("--all", action="store_true", help="打印全部玻璃类断言行（含已合规）")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    cats = {"glass": [], "llm": [], "test": []}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git", ".build", "DerivedData", "build")]
        for fn in files:
            if not fn.endswith(".swift"):
                continue
            full = os.path.join(base, fn)
            rel = os.path.relpath(full, root)
            try:
                lines = io.open(full, encoding="utf-8", errors="replace").read().splitlines()
            except OSError:
                continue
            for i, l in enumerate(lines):
                if "官方" not in l:
                    continue
                key = "test" if is_test(rel) else ("glass" if is_glass(rel) else ("llm" if is_llm(rel) else "llm"))
                cats[key].append((rel, i, l))
    total = sum(len(v) for v in cats.values())
    print(f"「官方」断言行现算：总 {total} ＝ 玻璃类 {len(cats['glass'])} ＋ LLM/提供商语境 {len(cats['llm'])} ＋ 测试 {len(cats['test'])}")
    if total != sum(len(v) for v in cats.values()):
        print("⇒ 口径不闭合（分类有漏/重）"); return 2
    if args.expect:
        want = [int(x) for x in args.expect.split(",")]
        got = [len(cats["glass"]), len(cats["llm"]), len(cats["test"])]
        if want != got:
            print(f"⇒ 与期望三分 {want} 不符（实测 {got}）：新增/删除了「官方」断言 ⇒ 必须重新审计并更新 §21.2 批次")
            return 2
    bad = []
    ok = []
    cross = []
    for rel, i, l in sorted(cats["glass"]):
        # 重新取该文件行以构块
        path = os.path.join(root, rel)
        src = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
        blk = anchor_window(src, i)
        neg = bool(NEG.search(l))
        # 逐字原文＝引文区间覆盖本行（状态机，见 quote_regions）；§号/docs 指针允许 ±1 行。
        has_anchor = bool(ANCHOR.search(blk)) or any(a <= i <= b for a, b in quote_regions(src))
        has_self = bool(SELF.search(blk))
        neg_ok = (not neg) or bool(NEG_GATE.search(blk))
        verdict = "OK" if ((has_anchor or has_self) and neg_ok) else "VIO"
        why = []
        if not (has_anchor or has_self):
            why.append("无锚点且未明示我方属性")
        if neg and not neg_ok:
            why.append("负结论未挂 §20/§21.3 检索门")
        rec = (rel, i + 1, " ".join(l.split())[:120], "；".join(why), neg)
        is_cross = bool(PROVIDER.search(blk)) and not bool(APPLE.search(blk))
        if is_cross:
            cross.append(rec)
        else:
            (ok if verdict == "OK" else bad).append(rec)
    if args.all:
        for rel, ln, t, _w, _n in ok:
            print(f"OK   {rel}:{ln}  {t}")
    if cross:
        print(f"—— 跨领域语境（提供商「官方」，§21.4 不入 Apple 锚点门）{len(cross)} 行，须提供商文档支撑（§21.6）：")
        for rel, ln, t, _w, _n in cross:
            print(f"XDOM {rel}:{ln}  {t}")
    for rel, ln, t, why, neg in bad:
        print(f"VIO  {rel}:{ln}  [{('C负' if neg else 'B正')}] {t}  ⇒ {why}")
    print(f"—— 玻璃类断言 {len(cats['glass'])} 行：Apple 断言合规 {len(ok)}，违规 {len(bad)}，跨领域另计 {len(cross)}")
    if bad:
        print("⇒ 处置：按 BENCHMARK §21.2 改法加限定语或挂锚点；加锚后须复跑本门 rc=0。")
        return 1
    print("⇒ 玻璃类「官方」断言全部有锚点或明示我方属性，负结论全部挂门。")
    return 0

if __name__ == "__main__":
    sys.exit(main())
