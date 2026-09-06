#!/usr/bin/env python3
"""bash 3.2「$var 紧跟多字节字符」缺陷 lint（QUALITY ㊸-5 工具化）。

缺陷机理（09-06 实测）：bash 3.2 取变量名时按**字节**扫描，紧跟 `$name` 的多字节字符
（全角括号／中文引号等）其首字节会被并入变量名 ⇒
  · `set -u` 下报 `unbound variable`（响亮失败）
  · 无 `set -u` 时**静默展开为空**（隐蔽得多：文案缺字、路径缺段，且看不出原因）
修法唯一：一律 `${name}`。本 lint 让「以后又写回 $name（」在门禁里红，而不是靠人记住。

判据（保守，宁少报不误报成群）：只报**代码位**里 `$name` 后紧跟非 ASCII 字节的情形；
  注释行／行内注释之后的部分不报（那里不会展开，报了只是噪声，会把门变成噪音源）。
rc: 0 无命中 / 1 有命中 / 3 用法或环境错。"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
if not os.path.isdir(ROOT):
    print(f"目录不存在：{ROOT}", file=sys.stderr)
    sys.exit(3)

# $name 后紧跟一个非 ASCII 字节（未被 ${...} 保护）
PAT = re.compile(rb"\$([A-Za-z_][A-Za-z0-9_]*)[\x80-\xff]")
SKIP_DIRS = {".git", ".build", "node_modules", "DerivedData", "dist", "__pycache__"}
hits, scanned = [], 0

for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for fn in sorted(filenames):
        if not fn.endswith((".sh", ".zsh")):
            continue
        path = os.path.join(dirpath, fn)
        try:
            raw = open(path, "rb").read().split(b"\n")
        except OSError as exc:  # 读不到不等于通过：明确报错退出
            print(f"❌ 读取失败 {path}: {exc}", file=sys.stderr)
            sys.exit(3)
        scanned += 1
        for idx, line in enumerate(raw, 1):
            stripped = line.lstrip()
            if stripped.startswith(b"#"):
                continue
            cut = line.split(b" # ")[0]  # 行内注释之后不展开，不报
            for m in PAT.finditer(cut):
                col = m.start() + 1
                hits.append((path, idx, col, m.group(1).decode("ascii"), cut.decode("utf-8", "replace").strip()))

if scanned == 0:
    print(f"⚠️ 未扫到任何 shell 脚本（ROOT={ROOT}）⇒ 判为无效扫描", file=sys.stderr)
    sys.exit(3)

for path, ln, col, name, line in hits:
    print(f"❌ {path}:{ln}:{col}: ${name} 后紧跟多字节字符（bash 3.2 按字节取变量名，会把它并入名字）"
          f" ⇒ 改 ${name} 为 ${{{name}}}｜{line[:90]}")
print(f"multibyte-var-lint: 扫描 shell 脚本 {scanned} 个，命中 {len(hits)} 处")
sys.exit(1 if hits else 0)
