#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""官方引文台账逐字复核器（09-05 终版，A 层静默；把 §18.5／§21 那一族错误做成有退出码的门）。

三个校验器的分工（互不替代）：
  apple-quote-index.sh   → 「我方文档写过这句吗」（防「官方不存在 X」越权）
  official-claim-lint.py → 「注释挂『官方』的人有没有挂锚点」（防过度归因）
  本工具                 → 「我方**声称官方逐字**的每一句，是否真的在它**自己声明的那条通道**
                           的归档语料里逐字存在？声称的 .swiftdoc 字节 offset 是不是短语起点？」

为什么必须分通道（§18.5 误判的直接产物）：.swiftdoc 承载 API 符号级 DocC 正文与官方示例，
在线 JSON 承载教程/HIG 正文，两条通道互为盲区——「另一条通道没有」既不等于「官方没有」，
也不等于「我方引文是编的」。故先归因、再要求命中**声明的那条通道**；
只在别的通道命中＝归因错误（CHANNEL），不算通过。

四条匹配口径（每条都是本轮实测出来的反例，勿放宽）：
 1) 弯/直引号与省略号互认（§23.1）：官方 ’ vs 我方 ' 曾造成假阴性；字节通道同样要归一。
 2) markdown ** 强调与反引号先剥；`[符号]` 是在线 JSON 的 topic 链接占位（§19.1），
    正文该位置本为空位 ⇒ prose 语料用 references 表还原官方 title，还原点计数、不冒充逐字。
 3) 在线 JSON 的正文是**逐 run 存**的：一句引文常跨两个 paragraph、链接两侧空白自带，
    直接把 run 用空格拼起来会得到 "HStack , VStack"，直接拼会得到 "HStack,VStack"，
    两者都不等于官方正文 ⇒ 拼接规则见 docc_prose()，改一处就要跑 --self-test。
 4) .swiftdoc 正文按硬换行存，每行前置二进制前奏（两种变体均实测）：
      "\n" + 节类型字节(0x00-0x1f) + 3×NUL + 长度字节 + 3×NUL + "/// "
    ⇒ 对原始字节 find 整句必然假阴性；本工具构造「正文投影 + 偏移映射」，
      包含判定在可读正文上做，offset 判定仍回落到原始字节（与 §18.1「短语起点」口径一致）。

 11) 历史留档区（`<!-- quote-verify:archive -->`，专存「我方写错的原句」）不参与判定；
     跳过类（中文自述/围栏命令/留档区/未声明出处）**不占用去重键**——否则同一句先出现在
     留档位置就会让后面真正的官方引文一起漏检（口径 12，本轮读代码时实测到的放行路径）。

退出码语义（绝不把「读不到」读成判定）：
  0 = 全部「声称官方逐字」的引文在其声明通道逐字命中，offset 声明全在容差内
  1 = 存在 MISS / CHANNEL / OFFSET
  2 = 语料或输入异常（归档缺失、文档缺失、语料为空）
用法: python3 tools/qa/quote-verify.py [--docs 文档...] [--evidence DIR] [--tolerance 16]
                                       [--verbose] [--show-advisory] [--self-test]
"""
import argparse
import bisect
import contextlib
import io
import glob
import json
import os
import re
import sys

# ---------------- 归因词表（就近优先；一条不沾 = 未声明官方出处 = ADVISORY，不计门禁）----------------
SDK_MARKS = (".swiftdoc", "swiftdoc", "offset", "swiftinterface", "SDK", "DocC")
ONLINE_MARKS = ("在线", "developer.apple.com", "JSON 通道", "通道③", "通道 ③", "HIG",
                "Human Interface", "Materials", "教程", "WWDC", "逐字稿", "通道④",
                "applying-liquid-glass", "hig-materials", "view-glasseffect", ".json",
                "glasseffectcontainer", "glass-tint", "accessibilityreducetransparency")
THIRD_MARKS = ("DeepSeek", "deepseek", "Ollama", "ollama", "上游", "社区", "thinking models", "npm")
OFFICIAL_MARKS = ("官方", "原文", "逐字", "Apple")

QUOTE_RE = re.compile(r'["“]([^"”]{20,})["”]')
OFFSET_RE = re.compile(r"offset[^\d]{0,4}([\d][\d,]{3,})")
DASH = re.compile(r"\.\.\.|…{1,2}|——|—")
SENT_SPLIT = re.compile(r"(?<=[.!?:])\s+(?=[A-Z])")
CJK = re.compile(r"[\u4e00-\u9fff]")


def curlies(t):
    for k, v in {"\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"'}.items():
        t = t.replace(k, v)
    return t


def norm(t):
    """我方引文与在线语料共用的宽松归一（只用于包含判定，不用于逐字宣称）。"""
    t = curlies(t)
    t = re.sub(r"<[^>]+>", " ", t)
    t = t.replace("**", "").replace("`", "")
    t = re.sub(r"\[[^\]]*\]", " ", t)
    t = t.replace("\u2014", " ").replace("\u2026", " ")
    return re.sub(r"\s+", " ", t).lower().strip()


def strip_md(q):
    return curlies(q.replace("**", "").replace("`", "")).strip()


def segments(q):
    """省略号/破折号/[链接] 都切段：占位与省略处官方正文本为空，只能分段要求命中。"""
    has_link = bool(re.search(r"\[[^\]]+\]", q))
    segs = []
    for p in DASH.split(q):
        segs += re.split(r"\[[^\]]+\]", p)
    segs = [x.strip(" ,;。.") for x in segs if len(x.strip(" ,;。.")) >= 16]
    return (segs or [q.strip(" ,;。.")]), has_link


def quote_forms(q):
    """由强到弱的候选形态，用最弱能命中的那条判定，并把形态如实报出来：
      WHOLE 整条连续存在（可称「逐字整句」）；
      SENTS 切成分句后每句逐字存在 ⇒ 我方引文是跨段/跨 run 拼接，不可自称一整句逐字；
      FRAGS 只有碎片段命中 ⇒ 有省略或链接占位被改写，属弱证据，须人工复核。"""
    plain = re.sub(r"\[([^\]]+)\]", r"\1", q)
    has_link = plain != q
    segs, _ = segments(q)
    sents = [x.strip(" ,;。.") for x in SENT_SPLIT.split(plain)]
    sents = [x for x in sents if len(x) >= 16]
    forms = [("WHOLE", [plain], has_link)]
    if len(sents) > 1:
        forms.append(("SENTS", sents, has_link))
    if segs and segs != [plain]:
        forms.append(("FRAGS", segs, has_link))
    return forms


# ---------------- 通道①：在线文档（DocC JSON / HTML / TXT）----------------
NO_SPACE_BEFORE = set(" ,.;:!?)]}、。，…")
NO_SPACE_AFTER = set("([{《“‘-")


def docc_prose(obj):
    """DocC JSON → 按文档顺序拼的正文；链接 run 用 references 的官方 title 还原。

    run 之间是否补空格按标点决定（口径 3）：后段以标点开头不补；前段以开括号结尾不补。
    返回 (正文, 链接还原次数, 该页 references 的 title 集合)。
    """
    refs = {}
    if isinstance(obj, dict) and isinstance(obj.get("references"), dict):
        for ident, meta in obj["references"].items():
            if isinstance(meta, dict) and isinstance(meta.get("title"), str):
                refs[ident.split("/")[-1].lower()] = meta["title"]
    out, restored = [], [0]
    titles = set(refs.values())

    def run(it):
        if isinstance(it, dict):
            t = it.get("type")
            if t == "text":
                out.append(it.get("text", ""))
            elif t == "code":
                out.append(it.get("code", ""))
            elif t == "reference":
                title = refs.get(str(it.get("identifier", "")).split("/")[-1].lower())
                if title:
                    out.append(title)
                    restored[0] += 1
            for k, v in it.items():      # 通用递归：emphasis/strong 等由它覆盖，不再单开分支
                if k in ("type", "text", "code", "identifier", "url", "title", "isActive"):
                    continue
                if isinstance(v, (list, dict)):
                    run(v)
        elif isinstance(it, list):
            for x in it:
                run(x)

    run(obj)
    parts = [x.strip() for x in out if x and x.strip()]
    text = ""
    for x in parts:
        if text and x[0] not in NO_SPACE_BEFORE and text[-1] not in NO_SPACE_AFTER:
            text += " "
        text += x
    return text, restored[0], titles


class Online:
    def __init__(self, d):
        self.items = []            # (文件名, prose, raw_norm, 链接还原数)
        self.prose_map = {}        # 文件名 → 归一后的正文（占位反取官方渲染时按位置用）
        self.titles = {}           # 文件名 → 该页 references 的官方 title 集（小写）
        files = []
        for pat in ("**/*.json", "**/*.html", "**/*.txt"):
            files += glob.glob(os.path.join(d, pat), recursive=True)
        for f in sorted(set(files)):
            b = os.path.basename(f)
            if b.startswith("REJECTED-") or b == "MANIFEST.txt":
                continue
            try:
                raw = open(f, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            prose, links, titles = "", 0, set()
            if b.endswith(".json"):
                try:
                    prose, links, titles = docc_prose(json.loads(raw))
                except Exception:
                    prose, links, titles = "", 0, set()
            self.items.append((b, norm(prose) if prose else "", norm(raw), links))
            self.titles[b] = {t.lower() for t in titles}
            self.prose_map[b] = norm(prose) if prose else ""

    def find(self, seg):
        n = norm(seg)
        if len(n) < 12:
            return None
        hits = [name for name, pr, _, _ in self.items if n and n in pr]
        if hits:
            return (hits, "prose")
        hits = [name for name, _, rw, _ in self.items if n in rw]
        return (hits, "raw") if hits else None

    def link_restored(self):
        return sum(x[3] for x in self.items)

    def __len__(self):
        return len(self.items)


    def placeholder_verify(self, q):
        """核验我方对 topic 链接的手工还原（§19.1 的坑只能这样兜住）。

        `[X]` 是**我方**照 references 表填回正文的符号名，官方 JSON 里该位置是空的。
        只核碎片段永远核不到它：本轮实测就漏过一条把官方 `GlassEffectContainer`
        写成 `[Namespace]` 的错引（P1:63）。而「逐个试配官方 title」也不够——
        同一句里两个占位同时写错时，改任一个都不能让整句配通（P1:63 正是这样）。
        ⇒ 改为**按位置反取**：先在正文里定位引文，再取「相邻字面片段之间」的官方渲染，
        与我方写的名字直接比对。返回 (是否全部正确, {我方写的: 官方实际渲染})。
        """
        parts = re.split(r"\[[^\]]+\]", q)
        phs = re.findall(r"\[([^\]]+)\]", q)
        if not phs or len(parts) != len(phs) + 1:
            return True, {}
        wrong = {}
        for name, pr, _, _ in self.items:
            if not pr:
                continue
            cur = pr.find(norm(parts[0]))
            if cur < 0:
                continue
            cur += len(norm(parts[0]))
            ok_all = True
            for i, ph in enumerate(phs):
                nxt = norm(parts[i + 1])
                if not nxt:
                    tail = pr[cur:cur + 60].strip()
                    official = tail.split(" ")[0].strip(".,;:")
                else:
                    j = pr.find(nxt, cur)
                    if j < 0 or j - cur > 80:
                        ok_all = False
                        break
                    official = pr[cur:j].strip().strip(".,;:")
                if official and official != norm(ph):
                    wrong[ph] = official
                    ok_all = False
                cur = (j if nxt and official else cur) + (len(nxt) if nxt else len(official))
            if ok_all and not wrong:
                return True, {}              # 该页正文里所有占位都与我方写法一致
        return (not wrong), wrong


# ---------------- 通道②：本机 SDK .swiftdoc（正文投影 + 原始字节偏移映射）----------------
PRELUDE = re.compile(r"\n[\x00-\x1f](?:[\x00-\xff]{0,10}?///[ \t]*|[\x00-\xff]{0,10}?(?=[A-Za-z0-9`“]))")
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
# 官方正文用 U+2019 等弯号，我方常写直号（§23.1）。latin-1 视图下弯号＝3 字符，整段替换。
LIG = {ch.encode("utf-8").decode("latin-1"): rep for ch, rep in
       {"\u2019": chr(39), "\u2018": chr(39), "\u201c": chr(34), "\u201d": chr(34),
        "\u2026": "..."}.items()}


class SwiftDoc:
    def __init__(self, path, label):
        self.label, self.path = label, path
        raw = open(path, "rb").read().decode("latin-1", errors="replace")
        out, offs = [], []
        self.wraps = len(PRELUDE.findall(raw))
        last_space = True

        def emit(chunk, base):
            nonlocal last_space
            i, n = 0, len(chunk)
            while i < n:
                key = next((k for k in LIG if chunk.startswith(k, i)), None)
                if key:
                    for c2 in LIG[key]:
                        out.append(c2)
                        offs.append(base + i)
                    i += len(key)
                    last_space = False
                    continue
                ch = " " if CONTROL.match(chunk[i]) else chunk[i]
                i += 1
                if ch == "`":
                    continue                       # 官方 ``Symbol`` 的定界符不属于正文
                if ch in " \t":
                    if last_space:
                        continue                   # 折叠空白必须在建映射时做，事后 re.sub 会错位的坑本轮实测过
                    out.append(" ")
                    offs.append(base + i - 1)
                    last_space = True
                    continue
                out.append(ch)
                offs.append(base + i - 1)          # 投影下标 ↔ 原始字节 offset 一一对应
                last_space = False

        pos = 0
        for mt in PRELUDE.finditer(raw):
            emit(raw[pos:mt.start()], pos)
            if not last_space:
                out.append(" ")
                offs.append(mt.start())
                last_space = True
            pos = mt.end()
        emit(raw[pos:], pos)
        self.text = "".join(out)
        self.map = offs

    def find(self, seg):
        """→ (原始字节 offsets, 是否跨硬换行)。"""
        needle = strip_md(seg)
        if len(needle) < 8:
            return None, False
        idx, hits, wrapped = 0, [], False
        while True:
            i = self.text.find(needle, idx)
            if i < 0:
                break
            start = self.map[i]
            end = self.map[min(i + len(needle) - 1, len(self.map) - 1)]
            hits.append(start)
            if end - start > len(needle) + 8:      # 跨度变长＝中间吃掉了前奏字节＝跨行
                wrapped = True
            idx = i + 1
            if len(hits) >= 8:
                break
        return (hits, wrapped) if hits else (None, False)

    def context(self, off, pre=40, post=300):
        """按**原始字节 offset**取周围正文（映射单调，bisect 反查投影下标）。"""
        p = bisect.bisect_left(self.map, off)
        return self.text[max(0, p - pre):p + post]


# ---------------- 引文抽取辅助 ----------------
ARCHIVE_OPEN = "<!-- quote-verify:archive -->"
ARCHIVE_CLOSE = "<!-- /quote-verify:archive -->"
ARCHIVE_MAX_LINES = 240


def archive_flags(lines):
    """口径 11：历史留档区（专门存档「我方曾写错的原句」的表格）不参与逐字判定。

    为什么必须显式豁免而不是删历史：本仓规矩是「保留历史＋追加更正」，§24.4 那张
    「原句留档」表本身就是审计痕迹。若复核器把留档的错句判成 MISS，作者让它变绿的
    最省事办法就是篡改历史 ⇒ 工具会反过来逼作者毁台账，这比漏判更严重。
    三条防泄漏边界（避免「一个注释吃掉整份文档」）：
      ① 只认精确的 HTML 注释标记（渲染不可见，也不会被误写成普通文字）；
      ② 遇**第二个** `##`/`###` 小标题自动关闭——标记写在标题上方时，第一个标题
         连同该节正文属留档区，下一个同级标题起恢复正常判定；
      ③ 硬行数上限 %d 行，超限部分**照常判定**（宁可多报不可假绿）并回传计数。
    返回 (flags, over_limit_lines)。
    """
    flags, active, opened_at, heads, over = [False] * len(lines), False, -1, 0, 0
    for i, ln in enumerate(lines):
        s = ln.strip()
        if ARCHIVE_OPEN in s:
            active, opened_at, heads = True, i, 0
        elif ARCHIVE_CLOSE in s:
            active = False
        elif active and re.match(r"^#{2,3}\s", s):
            heads += 1
            if heads >= 2:
                active = False
        if active and i - opened_at > ARCHIVE_MAX_LINES:
            over += 1
            continue
        if active:
            flags[i] = True
    return flags, over


def fence_lang(idx, lines):
    """引文所在围栏代码块的语言（块外＝None）。只看顶格 ``` 行，不解析内联围栏。"""
    lang, inside = None, False
    for i in range(min(idx, len(lines))):
        t = lines[i].lstrip()
        if lines[i].startswith("```"):
            inside, lang = (False, None) if inside else (True, (t[3:].strip() or "text"))
    return lang if inside else None


def in_note(line, col):
    """引文起点是否落在〔…〕旁注之内。旁注里的引文按**注记自身**的出处声明归因
    （本轮实测：把 SDK 变体写进更正注记后，按正文出处判道会把它误报成 CHANNEL）。"""
    depth = 0
    for i, ch in enumerate(line):
        if ch == "〔":
            depth += 1
        elif ch == "〕":
            depth = max(0, depth - 1)
        elif i >= col:
            return depth > 0
    return False


def strip_note(t):
    """剔除〔…〕更正/历史注记再参与归因。

    本轮实测：给引文追加「09-05 逐字复核」注记（注记里必然提到 `.swiftdoc`）之后，
    归因把**出处是开发者网站在线页**的行判成了 .swiftdoc 通道，凭空造出 6 条假 CHANNEL。
    〔…〕 是本仓「更正/历史」的固定写法，属**旁注**而非出处声明，故归因前先剥。
    """
    return re.sub(r"〔[^〕]*〕", " ", t)


def attribute(quote_line, context_lines):
    """就近归因：从引文行向上找**最近**一条含通道标记的行定性。
    不能把上文拼成一坨再判：同一节里常同时讨论 .swiftdoc 与在线 JSON，
    固定优先级会把在线引文误判成 .swiftdoc 引文（本轮实测的假 CHANNEL）。"""
    for src in [strip_note(quote_line)] + [strip_note(x) for x in reversed(context_lines)]:
        for marks, ch in ((THIRD_MARKS, "3p"), (SDK_MARKS, "sdk"), (ONLINE_MARKS, "online")):
            hit = next((m for m in marks if m in src), None)
            if hit:
                return ch, hit
    for src in [strip_note(quote_line)] + [strip_note(x) for x in reversed(context_lines)]:
        hit = next((m for m in OFFICIAL_MARKS if m in src), None)
        if hit:
            return "any", hit
    return None, None


def claimed_offset(quote_line, context_lines):
    """→ (offset, 与引文行的距离)。距离＝0 表示声明写在引文行上（该短语起点，严格核）；
    距离>0 表示声明来自上方小标题（§18.2 的块状写法：一个 offset 领若干条引文），
    这种声明只能核「引文是否落在该文档区域内」，拿它当短语起点会误报 Δ≈1000 字节。"""
    for dist, src in enumerate([quote_line] + list(reversed(context_lines[-6:]))):
        m = OFFSET_RE.search(src)
        if m:
            return int(m.group(1).replace(",", "")), dist
    return None, None


# ---------------- 主流程 ----------------
def scan(docs, online, sdk, tolerance, region, verbose, show_advisory):
    ref = next((x for x in sdk if x.label.endswith("-27")), sdk[0])

    def sdk_any(pieces):
        """每段在**任一份**归档 .swiftdoc 命中即算通道命中；位置优先取 27（§18.1 约定）。"""
        res = []
        for sg in pieces:
            best = None
            for x in sdk:
                offs, wrapped = x.find(sg)
                if offs and (best is None or x is ref):
                    best = (offs, wrapped, x.label)
                if x is ref and best:
                    break
            res.append(best)
        return res

    C = dict(WHOLE=0, SENTS=0, FRAGS=0, MISS=0, CHANNEL=0, OFFSET=0, PLACEHOLDER=0, ADV=0,
             LINK=0, WRAP=0, CJKSKIP=0, CODESKIP=0, ARCHIVESKIP=0)
    bad, judged, skip_seen, adv_seen = [], set(), set(), set()
    for d in docs:
        lines = open(d, encoding="utf-8", errors="replace").read().splitlines()
        flags, over = archive_flags(lines)
        if over:
            print("WARN     %s  留档区超 %d 行上限，超出部分照常判定（未豁免 %d 行）"
                  % (d, ARCHIVE_MAX_LINES, over))
        for ln, raw_line in enumerate(lines, 1):
            line = raw_line
            for mt in QUOTE_RE.finditer(line):
                q = mt.group(1)
                if not re.search(r"[A-Za-z]{4}", q):
                    continue
                if not re.match(r"^[A-Za-z]", q.strip()):
                    continue          # 官方整句必以字母开头；以逗号/反引号/代码符号起头的是我方代码碎片
                if len([w for w in q.split() if any(c.isalpha() for c in w)]) < 4:
                    continue
                key = norm(q)
                # 口径 12：分类按**出现位置**判，去重只去**计数**，绝不阻断后续判定。
                # 反例（本轮 self-test 当场抓出的两条 FAIL）：同一句先出现在中文自述/围栏
                # 命令/留档表里就把它记进跳过键，后文正文里真正的官方引文会被同一把键一起
                # 放过 ⇒ 判定必须只看 judged，跳过类各自用 skip_seen/adv_seen 防重复计数。
                if key in judged:
                    continue
                if CJK.search(q):
                    if key not in skip_seen:
                        C["CJKSKIP"] += 1                 # 中文正文里的引号＝我方自述，不作官方引文
                        skip_seen.add(key)   # 仅防重复计数：同一句在别处自称官方时照判
                    continue
                if fence_lang(ln - 1, lines) not in (None, "swift"):
                    if key not in skip_seen:
                        C["CODESKIP"] += 1                    # bash/python 块内是我方命令与输出
                        skip_seen.add(key)
                    if show_advisory:
                        print("ADV      %s:%d  围栏代码块内文本（不计门禁）%s" % (d, ln, q[:58]))
                    continue
                if flags[ln - 1]:                         # §24.4 型历史留档区
                    if key not in skip_seen:
                        C["ARCHIVESKIP"] += 1
                        skip_seen.add(key)
                    if show_advisory:
                        print("ADV      %s:%d  历史留档区原句（不参与判定）%s" % (d, ln, q[:58]))
                    continue
                context = lines[max(0, ln - 13):ln]
                if in_note(line, mt.start()):
                    note = "".join(re.findall(r"〔[^〕]*〕", line))
                    chan, mark = attribute(note, [])
                    if chan is None:
                        chan, mark = "any", "旁注引文"
                else:
                    chan, mark = attribute(line, context)
                if chan is None:
                    if key not in adv_seen:
                        C["ADV"] += 1
                        adv_seen.add(key)
                    if show_advisory:
                        print("ADV      %s:%d  未声明官方出处  %s" % (d, ln, q[:66]))
                    continue
                if chan == "3p":
                    if key not in adv_seen:
                        C["ADV"] += 1
                        adv_seen.add(key)
                    if show_advisory:
                        print("ADV      %s:%d  第三方/上游引文（本机未归档该通道语料）%s" % (d, ln, q[:58]))
                    continue
                judged.add(key)
                best = None
                for fname, pieces, has_link in quote_forms(q):
                    oh = [online.find(x) for x in pieces]
                    sh = sdk_any(pieces)
                    if all(oh) or all(sh):
                        best = [fname, pieces, oh, sh, all(sh), all(oh), has_link]
                        break
                if best is None:
                    fname, pieces, has_link = quote_forms(q)[-1][0], quote_forms(q)[-1][1], False
                    oh = [online.find(x) for x in pieces]
                    sh = sdk_any(pieces)
                    C["MISS"] += 1
                    bad.append((d, ln, "MISS"))
                    print("MISS    %s:%d  归因=%s(%s) 最弱形态 %s 仍不命中  %s"
                          % (d, ln, chan, mark, fname, q[:60]))
                    for x, o, h in zip(pieces, sh, oh):
                        if not (o and o[0]) and not h:
                            print("        缺段: %s" % x[:62])
                    continue
                fname, pieces, oh, sh, sdk_found, online_found, has_link = best
                if has_link and chan in ("online", "any"):
                    ok_ph, wrong = online.placeholder_verify(q)
                    if not ok_ph:
                        C["PLACEHOLDER"] += 1
                        bad.append((d, ln, "PLACEHOLDER"))
                        print("PLACEHOLD %s:%d  我方链接占位还原与官方 title 不符：%s"
                              % (d, ln, "；".join("官方=%s（我方写成 [%s]）" % (v, k)
                                                 for k, v in sorted(wrong.items()))))
                        print("          %s" % q[:64])
                        continue
                if chan == "sdk" and not sdk_found:
                    C["CHANNEL"] += 1
                    bad.append((d, ln, "CHANNEL"))
                    print("CHANNEL %s:%d  自称 .swiftdoc 通道，实测只在在线命中（%s）\n        %s"
                          % (d, ln, (oh[0][0] if oh[0] else ["?"])[0], q[:66]))
                    continue
                if chan == "online" and not online_found:
                    C["CHANNEL"] += 1
                    bad.append((d, ln, "CHANNEL"))
                    print("CHANNEL %s:%d  自称在线通道，实测只在 .swiftdoc 命中  %s" % (d, ln, q[:62]))
                    continue
                note = ""
                off_claim, off_dist = claimed_offset(line, context)
                if off_claim is not None and chan in ("sdk", "any"):
                    if sdk_found:
                        # 同一句在 .swiftdoc 里常多处出现（abstract 表＋符号文档区），
                        # 必须取「离声明最近」的命中；取首个会凭空量出 20 万字节的假偏差。
                        near = [min(hit[0], key=lambda o: abs(o - off_claim)) for hit in sh if hit]
                        got = min(near)
                        wrapped = any(hit[1] for hit in sh if hit)
                        delta = got - off_claim
                        if wrapped:
                            C["WRAP"] += 1
                        if off_dist == 0:               # 声明与引文同行＝这就是该短语的起点，严格核
                            note = "offset 实测=%s 声明=%s Δ=%s%s" % (
                                got, off_claim, delta, "（跨硬换行量取）" if wrapped else "")
                        else:                           # 声明在上文小标题＝整块文档区起点，只能核「是否落在区内」
                            note = ("引文落在声明区域 %s 之内（起点差 %+d，区上限 %s）"
                                    % (off_claim, delta, region) if abs(delta) <= region else
                                    "引文起点距声明区域 %s 为 %+d，超出区上限 %s" % (off_claim, delta, region))
                            delta = 0 if abs(delta) <= region else delta
                    else:
                        delta, note = None, "声明 offset 但 .swiftdoc 无该形态，无法量偏移"
                    if abs(delta) > tolerance:
                        C["OFFSET"] += 1
                        bad.append((d, ln, "OFFSET"))
                        print("OFFSET  %s:%d  %s  %s" % (d, ln, note, q[:52]))
                        continue
                if has_link:
                    C["LINK"] += 1
                C[fname] += 1
                if verbose:
                    print("OK-%-5s %s:%d  %s %s" % (fname, d, ln, note, q[:50]))
    return C, bad


def _scan_fixture(text, online, sdk):
    """把一段 markdown 夹具落到临时文件跑 scan()，返回计数 dict（判定输出静默丢弃）。"""
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "fixture.md")
        io.open(p, "w", encoding="utf-8").write(text)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            C, _bad = scan([p], online, sdk, 16, 6000, False, False)
        return C, buf.getvalue()


FAKE = "Liquid Glass samples content outside the window boundary"   # 已实测：官方两通道皆无此句


def self_test(online, sdk):
    """口径回归：改任何匹配规则都必须先过这四条（每条都对应本轮踩过的一次坑）。"""
    ok = True
    cases = [
        ("在线 prose 拼接：链接两侧标点", lambda: online.find(
            "the spacing of an interior HStack, VStack, or other layout container") is not None, True),
        ("在线跨段整句（两段 paragraph 拼成的一句）", lambda: online.find(
            "Renders a shape anchored behind a view with the Liquid Glass material. "
            "Applies the foreground effects of Liquid Glass over a view.") is not None, True),
        ("字节通道：.swiftdoc 硬换行整句（官方写 glassEffect(_:in) 无冒号，用例照官方写）",
         lambda: sdk[0].find(
             "You use a glass effect container with the View/glassEffect(_:in) modifier. "
             "Each view with a glass effect contributes a shape rendered with the physical glass "
             "material to a set of shapes.")[0] is not None, True),
        ("字节通道：不存在的句子必须不命中", lambda: sdk[0].find(FAKE)[0] is None, True),
    ]
    # 口径 11/12 的回归用 scan 级夹具（改豁免规则或去重顺序都必须先过这两条）
    c11, _ = _scan_fixture(
        "## 甲 留档节\n%s\n### 表格\n.swiftdoc 旧写法\"%s\"\n## 乙 正文节\n.swiftdoc 逐字\"%s\"\n"
        % (ARCHIVE_OPEN, FAKE, FAKE), online, sdk)
    cases.append(("口径11：留档区豁免一条＋遇第二个小标题自动关闭后照判一条",
                  (c11["ARCHIVESKIP"], c11["MISS"]), (1, 1)))
    c12, _ = _scan_fixture(
        "```bash\necho \"%s\"\n```\n## 正文\n.swiftdoc 逐字\"%s\"\n" % (FAKE, FAKE), online, sdk)
    cases.append(("口径12：同句先出现在 bash 块不占用去重键，正文自称官方仍须判 MISS",
                  (c12["CODESKIP"], c12["MISS"]), (1, 1)))
    for item in cases:
        name, fn, want = item[0], item[1], item[2]
        try:
            got = fn() if callable(fn) else fn
            got = bool(got) if isinstance(got, (bool, int, str, tuple)) and not isinstance(got, tuple) else got
        except Exception as e:
            got, want = "异常 %s" % e, None
            name += "（异常）"
        print("%s  %s%s" % ("PASS" if got == want else "FAIL", name,
                            "" if got == want else "  实测=%r 期望=%r" % (got, want)))
        ok = ok and got == want
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--docs", nargs="*",
                    default=["docs/P1_GLASS_API_VERIFICATION.md", "docs/BENCHMARK_CHECKLIST.md"])
    ap.add_argument("--evidence", default=os.path.expanduser("~/harness-wt/evidence"))
    ap.add_argument("--tolerance", type=int, default=16,
                    help="同行 offset 声明与实测短语起点的容差字节")
    ap.add_argument("--region", type=int, default=6000,
                    help="上方小标题声明 offset 时，允许引文起点落在声明点之后多少字节内（文档区跨度）")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--show-advisory", action="store_true")
    ap.add_argument("--self-test", action="store_true", help="只跑匹配口径回归用例")
    a = ap.parse_args()

    docs = [d for d in a.docs if os.path.isfile(d)]
    if not docs:
        print("❌ 待审文档全部不存在：%s" % a.docs, file=sys.stderr)
        return 2
    online = Online(os.path.join(a.evidence, "apple"))
    sdk = []
    for p in sorted(glob.glob(os.path.join(a.evidence, "sdk", "*.swiftdoc"))):
        m = re.search(r"SwiftUICore-([0-9.]+)-", os.path.basename(p))
        sdk.append(SwiftDoc(p, "swiftdoc-" + (m.group(1) if m else os.path.basename(p))))
    if not online.items or not sdk:
        print("❌ 语料不完整：在线 %d 份／.swiftdoc %d 份（拒绝把「读不到」读成判定）"
              % (len(online), len(sdk)), file=sys.stderr)
        return 2
    if a.self_test:
        return self_test(online, sdk)

    C, bad = scan(docs, online, sdk, a.tolerance, a.region, a.verbose, a.show_advisory)
    total = (C["WHOLE"] + C["SENTS"] + C["FRAGS"] + C["MISS"] + C["CHANNEL"]
             + C["OFFSET"] + C["PLACEHOLDER"] + C["ADV"])
    print("—— 台账引文现算 %d 条（去重后）：整句逐字 %d／跨段拼接整句可核 %d／仅碎片段可核 %d"
          "／MISS %d／CHANNEL %d／OFFSET %d／占位还原错 %d／不计门禁 %d" %
          (total, C["WHOLE"], C["SENTS"], C["FRAGS"], C["MISS"], C["CHANNEL"],
           C["OFFSET"], C["PLACEHOLDER"], C["ADV"]))
    print("   形态计数：%s" % "／".join("%s=%d" % (k, v) for k, v in sorted(C.items())))
    print("   历史留档区豁免 %d 条（标记 %s，自动遇第二个小标题关闭＋%d 行硬上限）"
          % (C["ARCHIVESKIP"], ARCHIVE_OPEN, ARCHIVE_MAX_LINES))
    print("   其中链接占位 %d 条走 references 还原（在线共还原 %d 处）；.swiftdoc 偏移跨硬换行量取 %d 条"
          % (C["LINK"], online.link_restored(), C["WRAP"]))
    print("   语料：在线 %d 份＋.swiftdoc %d 份（%s）" % (len(online), len(sdk), "／".join(x.label for x in sdk)))
    if bad:
        print("⇒ MISS/CHANNEL/OFFSET ≠ 「官方没写过」：须按 §20.2 四步门逐条定性"
              "（①全仓检索已入册引文 ②.swiftdoc ③在线 JSON ④必要时补归档）后才可改文档。待定性 %d 条。" % len(bad))
        return 1
    print("⇒ 台账内所有「声称官方逐字」的引文均在**其声明通道**的归档语料中逐字命中，offset 声明全在容差内。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
