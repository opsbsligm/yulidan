#!/usr/bin/env bash
# 官方引文反向索引 ＋ 负结论前置检索门（09-05 §18.5 误判的直接产物）。
# 存在理由：同一篇官方文章的引文分散在 BENCHMARK 多个小节与代码注释里，
# 拿单一通道的阴性就断言「官方无此表述」＝越权负结论（真实发生过，见 §18.5 更正）。
#
# 用法：
#   tools/qa/apple-quote-index.sh                    # 列出全部已入册官方引文（章节／行号／首句）
#   tools/qa/apple-quote-index.sh --query "at rest"  # 断言「官方不存在 X」之前的强制检索
# 退出码：列表模式恒 0；query 模式命中 0／未命中 1（未命中＝阴性，须再走在线 JSON 通道才可下负结论）。
set -euo pipefail
DOCS=(docs/BENCHMARK_CHECKLIST.md docs/P1_GLASS_API_VERIFICATION.md P1_STAGE_REPORT.md QUALITY_REPORT.md)
if [ "${1:-}" = "--query" ]; then
  [ $# -ge 2 ] || { echo "用法: $0 --query \"<官方原文关键短语>\"" >&2; exit 2; }
  q="$2"; found=0
  for f in "${DOCS[@]}"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      ln="${line%%:*}"; rest="${line#*:}"
      printf 'HIT %s:%s  %s\n' "$f" "$ln" "${rest:0:150}"; found=1
    done < <(grep -in -- "$q" "$f" || true)
  done
  if [ "$found" -eq 0 ]; then
    echo "MISS 我方文档内未检索到「${q}」"
    echo "⇒ 阴性不充分：还须 ① 查代码注释（grep -rn 于 Sources）② 在线 JSON 通道（tutorials/data/documentation/…）与 ③ .swiftdoc 双通道皆阴性，才可下「官方无此表述」。"
    exit 1
  fi
  echo "⇒ 我方文档**已有**该引文（$found 处以上），禁止再下「官方无此表述」类负结论。"
  exit 0
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
