#!/usr/bin/env python3
"""内容活性自证（QUALITY ㊷-2 固化的门槛）。

存在理由：09-06 差点把「rc=0 的 429KB 截图」当成有效证据——若它是黑屏/纯色底图，
后续所有对标结论都会建立在不存在的证据上。故「取到了产物」必须自证内容活性。

用法：window-live-check.py <png路径> [锁态标注]
退出码：0 活性达标 / 4 不达标（产物作废，禁止作为证据引用）
判据保守：黑屏与纯色底图 ⇒ 唯一色≈1、标准差≈0，必被拦；真实 UI 远高于该量级。
"""
import os
import sys
from PIL import Image

if len(sys.argv) < 2:
    print("用法: window-live-check.py <png路径> [锁态标注]", file=sys.stderr)
    sys.exit(3)
path = sys.argv[1]
tag = sys.argv[2] if len(sys.argv) > 2 else ""

if not os.path.exists(path) or os.path.getsize(path) == 0:
    print("活性自证：无产物／零字节 ⇒ 证据无效")
    sys.exit(4)

im = Image.open(path).convert("RGB")
px = list(im.resize((64, 64)).getdata())
n = len(px)
mean = [sum(c[i] for c in px) / n for i in range(3)]
sd = (sum(sum((c[i] - mean[i]) ** 2 for i in range(3)) for c in px) / (n * 3)) ** 0.5
uniq = len(set(px))
print(f"活性自证: {im.size[0]}x{im.size[1]} 唯一色={uniq}/4096 "
      f"标准差={sd:.1f} 均值=({mean[0]:.0f},{mean[1]:.0f},{mean[2]:.0f}) {tag}".rstrip())
if uniq < 8 or sd < 1.0:
    print("⇒ 活性不达标（疑似空图／黑屏／底图）：本产物不得作为证据引用")
    sys.exit(4)
print("⇒ 活性达标。跨窗对比仍是排除「同一底图」的最强证据（见 QUALITY ㊷-2）")
