#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从本机 SDK 的 .swiftdoc 提取 Apple 官方文档正文（含官方示例代码原文）。

为什么需要它：铁律 1 的查证通道此前只有两条（.swiftinterface 签名 / 在线文档），
而 .swiftdoc 里存的是**每个公开符号的 DocC 文档全文与示例**，比在线文档更贴合本机 SDK 版本，
且零网络、零前台、锁屏可跑（静默铁律 A 层）。见 docs/BENCHMARK_CHECKLIST.md §18。

用法：
    tools/qa/swiftdoc-extract.py "A view that combines multiple glass shapes"
    tools/qa/swiftdoc-extract.py --offsets-only glassEffectTransition
    tools/qa/swiftdoc-extract.py --all --window 4000 "the sooner blending begins"
    tools/qa/swiftdoc-extract.py --framework AppKit --sdk /Path/MacOSX27.sdk "..."
输出：每个命中的 byte offset + 该处窗口内文档正文（已剥离 NUL 分片符与二进制噪声）。
"""
import argparse
import os
import re
import subprocess
import sys

# 查找顺序：显式 --sdk > xcrun 默认 SDK > Xcode-beta（27 beta 基线）> Xcode
BETA = "/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"
PROD = "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs"


def candidate_sdks():
    out = []
    try:
        r = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            out.append(r.stdout.strip())
    except Exception:
        pass
    for root in (BETA, PROD):
        if os.path.isdir(root):
            for name in sorted(os.listdir(root), reverse=True):  # 27.* 优先
                p = os.path.join(root, name)
                if os.path.isdir(p):
                    out.append(p)
    return out


def find_doc(sdk, framework):
    base = os.path.join(sdk, "System", "Library", "Frameworks", framework + ".framework",
                        "Versions", "A", "Modules")
    if not os.path.isdir(base):
        return None
    for mod in sorted(os.listdir(base)):
        if not mod.endswith(".swiftmodule"):
            continue
        mdir = os.path.join(base, mod)
        names = sorted(os.listdir(mdir))
        # 优先 arm64e-apple-macos（本机 SDK 实际存在的切片名），再退而求其次
        for want in ("arm64e-apple-macos.swiftdoc", "arm64-apple-macos.swiftdoc"):
            if want in names:
                return os.path.join(mdir, want)
        for n in names:
            if n.endswith("-apple-macos.swiftdoc"):
                return os.path.join(mdir, n)
    return None


def clean(b):
    s = b.decode("utf-8", errors="ignore").replace("\x00", "")
    s = re.sub(r"[ \t]+", " ", s)
    # 文档正文行以 "/// " 起始；保留原文行序，仅去掉明显的二进制短噪声片段
    lines = [ln.rstrip() for ln in s.split("\n")]
    keep = []
    for ln in lines:
        t = ln.strip()
        if not t:
            continue
        if len(t) < 3:
            continue
        keep.append(ln)
    return "\n".join(keep)


def main():
    ap = argparse.ArgumentParser(description="提取本机 SDK .swiftdoc 内的 Apple 官方文档正文")
    ap.add_argument("phrase", help="官方文档中的 ASCII 子串（大小写敏感；建议取整句片段）")
    ap.add_argument("--framework", default="SwiftUICore",
                    help="framework 名（27 beta 玻璃 API 在 SwiftUICore，非 SwiftUI）")
    ap.add_argument("--sdk", default=None, help="显式 SDK 路径（默认自动按 xcrun→Xcode-beta→Xcode 查找）")
    ap.add_argument("--pre", type=int, default=200, help="命中点前向窗口字节数")
    ap.add_argument("--window", type=int, default=2600, help="命中点后向窗口字节数")
    ap.add_argument("--all", action="store_true", help="输出全部命中（默认仅第一处）")
    ap.add_argument("--offsets-only", action="store_true", help="只列命中偏移与文件大小")
    args = ap.parse_args()

    sdks = [args.sdk] if args.sdk else candidate_sdks()
    doc = None
    for s in sdks:
        if not s or not os.path.isdir(s):
            continue
        doc = find_doc(s, args.framework)
        if doc:
            break
    if not doc:
        sys.stderr.write("未找到 %s 的 .swiftdoc（试过：%s）\n" % (args.framework, ", ".join(sdks)))
        return 3

    raw = open(doc, "rb").read()
    needle = args.phrase.encode("utf-8")
    offs = []
    pos = raw.find(needle)
    while pos != -1:
        offs.append(pos)
        if not args.all:
            break
        pos = raw.find(needle, pos + 1)
    print("DOC-FILE %s (%d bytes)" % (doc, len(raw)))
    if not offs:
        sys.stderr.write("未命中短语：%s\n" % args.phrase)
        return 4
    if args.offsets_only:
        print("HITS " + " ".join(str(o) for o in offs))
        return 0
    for i, o in enumerate(offs):
        print("\n===== HIT %d @ byte offset %d =====" % (i + 1, o))
        print(clean(raw[max(0, o - args.pre):o + args.window]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
