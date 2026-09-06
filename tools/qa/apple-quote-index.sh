#!/usr/bin/env bash
# 官方引文反向索引 ＋ 负结论前置检索门（09-05 §18.5 误判的直接产物）。
# 存在理由：同一篇官方文章的引文分散在 BENCHMARK 多个小节与代码注释里，
# 拿单一通道的阴性就断言「官方无此表述」＝越权负结论（真实发生过，见 §18.5 更正）。
#
# 用法：
#   tools/qa/apple-quote-index.sh                       # 列出全部已入册官方引文（章节／行号／首句）
#   tools/qa/apple-quote-index.sh --query "at rest"     # 断言「官方不存在 X」之前的强制检索
#   QUOTE_INDEX_DOCS="a.md b.md" ... --query "..."      # 自测／扩展用：覆盖被检索文档集
# 退出码：列表模式恒 0；query 模式命中 0／未命中 1（未命中＝阴性，须再走在线 JSON 通道才可下负结论）。
#
# ★检索必须跨物理行（09-06 实测教训，勿回退成裸 grep）：在册引文按 markdown 排版存在**硬换行**，
#   例 BENCHMARK:166-167「…geometry of the shapes⏎  themselves** to determine…」——
#   逐行 grep（含先剥 ** 的写法）对这类跨行短语恒假阴性，会让「官方无此表述」的错误负结论
#   重新通过闸门。故内置三级匹配 L1/L2/L3；L3 只在**单条目内部**折行，绝不跨条目拼接
#   （防止造出官方从未连写的假引文），且对「疑似跨行却没被吸收」的排版响亮告警。
set -euo pipefail
DOCS=(docs/BENCHMARK_CHECKLIST.md docs/P1_GLASS_API_VERIFICATION.md P1_STAGE_REPORT.md QUALITY_REPORT.md)
if [ -n "${QUOTE_INDEX_DOCS:-}" ]; then
  DOCS=($QUOTE_INDEX_DOCS)   # 词分词是刻意的：文档集仅允许空格分隔的无空格路径（bash 3.2 兼容口径）
fi
if [ "${1:-}" = "--query" ]; then
  [ $# -ge 2 ] || { echo "用法: $0 --query \"<官方原文关键短语>\"" >&2; exit 2; }
  python3 - "$2" "${DOCS[@]}" <<'PY'
import io, re, sys

query, paths = sys.argv[1], sys.argv[2:]


def strip_md(s):
    """剥 **加粗**／`代码` 标记：只删字符，不增删行 ⇒ 行号与原文一致。"""
    return s.replace("**", "").replace("`", "")


def ws_pattern(s):
    """查询 → 「字面 token + 空白可宽容」正则：官方排版里的多空格／折行产生的
    单空格一律容忍；token 本体始终按字面匹配（不把查询当正则，避免误伤与报错）。"""
    toks = [re.escape(t) for t in re.sub(r"\s+", " ", strip_md(s)).strip().split()]
    return re.compile(r"[\s]+".join(toks), re.IGNORECASE) if toks else None


def kind_of(s):
    """条目类型：list / quote / plain / None（None＝不是条目起始行）。"""
    if re.match(r"^\s*(?:[-*]\s+|\d+\.\s+)", s):
        return "list"
    if re.match(r"^\s*>", s):
        return "quote"
    if s.lstrip().startswith('"'):
        return "plain"
    return None


def absorbable(s, kind):
    """可吸收进当前条目的续行。★按条目类型严格区分——09-06 变异实测抓到：
    若不加区分地接受 `>` 行，引用块会被吞进前一个列表项，把两条互不相干的在册
    引文连读成官方从未写过的句子（＝造假的证据源）。故：
      list  只吸收缩进正文行（`>` 行＝另一块，拒收）；
      quote 吸收 `>` 续行与缩进正文行；
      plain 只吸收缩进正文行。"""
    if not s.strip():
        return False
    body = s.strip()
    if kind == "quote":
        if re.match(r"^\s*>", s):
            body = re.sub(r"^\s*>+\s?", "", s).strip()
        elif not s.startswith((" ", "\t")):
            return False
    else:
        if not s.startswith((" ", "\t")):
            return False                  # 无缩进＝平级新行，不属本条目
        if re.match(r"^\s*>", s):
            return False                  # 列表／正文条目后面出现的 `>` 行一律视为另一块
    if re.match(r"^(?:[-*]\s+|\d+\.\s+|[>#|`])", body):
        return False                      # 新列表项／标题／表格／代码块＝另一结构单元
    return True


def quote_open_unclosed(t):
    """剥标记后的文本里：存在开引号但找不到闭合引号 ⇒ 该引文跨到了下一物理行。"""
    i = t.find('"')
    return i != -1 and t.find('"', i + 1) == -1


def fold_blockquote(s):
    """把引用块续行的 `>` 标记剥掉，使折行文本可连读。"""
    return re.sub(r"^\s*>+\s?", "", s).strip()


def scan(path):
    lines = io.open(path, encoding="utf-8").read().split("\n")
    hits, warns = [], []
    pat1, pat2 = ws_pattern(query), ws_pattern(strip_md(query))

    if pat1:
        for i, l in enumerate(lines, 1):
            if pat1.search(l):
                hits.append((f"{path}:{i}", "[L1 原文逐行]", l.strip()[:150], None))
    if not hits and pat2:
        for i, l in enumerate(lines, 1):
            if pat2.search(strip_md(l)):
                hits.append((f"{path}:{i}", "[L2 剥 **／` 后逐行]", l.strip()[:150], None))
    if hits and any(h[1].startswith("[L2") for h in hits):
        print(f"NOTE {path}：命中处含 markdown 标记，已剥除 **／反引号（行号＝原文行号）")

    if not hits and pat2:
        i, n = 0, len(lines)
        while i < n:
            kind = kind_of(lines[i])
            # ★折叠起点必须是「本行含 ASCII 引号的条目起始行」。不含引号的条目（如日志日期
            #   标题 `> **2026-09-06（…）**：`）不是引文单元；若让它当起点，会把整条日志的多个
            #   段落吞成一个巨块——既造出同条目内跨段落的假连读，又使引号闭合判据失效（09-06 实测）。
            if kind is None or '"' not in strip_md(lines[i]):
                i += 1
                continue
            start = i
            block = [fold_blockquote(lines[i])]
            folded = re.sub(r"\s+", " ", strip_md(" ".join(x.strip() for x in block))).strip()
            j = i + 1
            while j < n and absorbable(lines[j], kind):
                if '"' in folded and not quote_open_unclosed(folded):
                    break          # 引文已在本行闭合 ⇒ 绝不再吞同一条目的下一句
                block.append(fold_blockquote(lines[j]))
                j += 1
                folded = re.sub(r"\s+", " ", strip_md(" ".join(x.strip() for x in block))).strip()
            if pat2.search(folded):
                rng = str(start + 1) if j - start == 1 else f"{start + 1}-{j}"
                hits.append((f"{path}:{rng}", "[L3 条目折行]", folded[:200],
                             f"该引文在源文件里跨 {j - start} 个物理行（L{rng}），逐行 grep 永不命中；"
                             f"折叠单元＝单条引文，未跨条目、未跨段落拼接。"))
            # 响亮告警：开引号存在却始终没闭合 ⇒ 有未被吸收的跨行排版，本文件阴性不充分。
            # 绝不静默放过，否则闸门会替越权负结论背书。
            if quote_open_unclosed(folded):
                warns.append(f"{path}:{start + 1} 引文开引号未闭合且 L3 未吸收该续行"
                             f"⇒ 该排版未覆盖，本文件阴性不充分")
            i = j if j > i else i + 1
    return hits, warns


total_hit, total_warn = 0, []
for p in paths:
    try:
        h, w = scan(p)
    except OSError as e:
        # 响亮失败：被检索文档读不到＝闸门自身失效，绝不能静默跳过后返回「未检索到」，
        # 那等于用一次根本没跑的检索去给「官方无此表述」背书（与「判据不得返回空集合」同律）。
        print(f"FATAL 被检索文档不可读：{p}（{e}）⇒ 本次检索无效，禁止据此下任何负结论")
        sys.exit(3)
    for loc, tag, snippet, note in h:
        print(f"HIT {loc} {tag}  {snippet}")
        if note:
            print(f"     ⤷ {note}")
    total_hit += len(h)
    total_warn += w

if not total_hit:
    print(f"MISS 我方文档内未检索到「{query}」")
    for w in total_warn:
        print(f"WARN {w}")
    print("⇒ 提示：查询请用裸片段（不带 * 与反引号）；跨行短语可直接给整段，L3 会折行匹配。")
    print("⇒ 阴性不充分：还须 ① 查代码注释（grep -rn 于 Sources）② 在线 JSON 通道"
          "（tutorials/data/documentation/…）与 ③ .swiftdoc 双通道皆阴性，才可下「官方无此表述」。")
    sys.exit(1)
print("⇒ 我方文档**已有**该引文，禁止再下「官方无此表述」类负结论。")
PY
  exit $?
fi
python3 - <<'PY'
import io, re
p = "docs/BENCHMARK_CHECKLIST.md"
sec = None
n = 0
for i, l in enumerate(io.open(p, encoding="utf-8"), 1):
    m = re.match(r"^#{2,3}\s+(§?\d[\d\.]*)[ \t]*(.*)", l)
    if m:
        sec = (m.group(1) + " " + m.group(2).strip()).strip()
    b = l.strip()
    if b.startswith('> "') or b.startswith('- "') or b.startswith('- "**') or b.startswith('> "**'):
        n += 1
        print(f"{sec:34s} L{i:<5} {b[:110]}")
print(f"—— 已入册官方引文 {n} 条")
PY
