#!/usr/bin/env python3
r"""Markdown 表格列数一致性检查（转义感知）。

用途：台账/手册类 md 是用户实际阅读面，表格列数错位＝内容串行（首列缺失会让整行左移）。
判据：表头行与分隔行构成一个表块；块内每个数据行的「未转义 |」切分格数须与表头相等。
      `\|` 是 GFM 官方管道转义，先屏蔽再切分（朴素计数会把正确转义的行误报）。
退出码：0＝全部一致；1＝存在不一致（供 CI/门禁直接消费）。09-05 教训：守卫类工具必须实测失败路径退出码。
用法：md-table-lint.py [文件或目录 ...]（默认 docs + 两份报告）
"""
import io
import os
import re
import sys

SEP = re.compile(r"^\|[\s:|-]+\|$")


def cells(line):
    s = line.strip()
    if not (s.startswith("|") and s.endswith("|")):
        return None
    return s[1:-1].replace("\\|", "\0").split("|")


def lint(path):
    lines = io.open(path, encoding="utf-8").read().split("\n")
    bad, i, n = [], 0, len(lines)
    while i < n:
        if lines[i].strip().startswith("|") and i + 1 < n and SEP.match(lines[i + 1].strip()):
            head = cells(lines[i])
            if head is None:
                i += 1
                continue
            k = len(head)
            j = i + 2
            while j < n and lines[j].strip().startswith("|"):
                row = cells(lines[j])
                if row is None or len(row) != k:
                    side = "尾部缺格" if row is not None and lines[j].strip().endswith("|") else "行尾无 |"
                    bad.append((j + 1, k, None if row is None else len(row), side, lines[j].strip()[:70]))
                j += 1
            i = j
        else:
            i += 1
    return bad


def targets(args):
    out = []
    for a in args:
        if os.path.isdir(a):
            for root, _dirs, fs in os.walk(a):
                out += [os.path.join(root, f) for f in sorted(fs) if f.endswith(".md")]
        elif a.endswith(".md"):
            out.append(a)
    return out


def main(argv):
    args = argv[1:] or ["docs", "QUALITY_REPORT.md", "P1_STAGE_REPORT.md"]
    files = targets(args)
    if not files:
        print("无可检查的 md 文件", file=sys.stderr)
        return 2
    total = 0
    for f in files:
        for ln, k, got, _side, preview in lint(f):
            print(f"{f}:{ln} 列数不符 表头 {k} 列／本行 {got} 列 :: {preview}")
            total += 1
    print(f"检查 {len(files)} 个文件，列数不一致 {total} 处")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
