#!/usr/bin/env bash
# window-shot.sh 的常驻自测（六向）——把一次性手测变成可重跑的 rc（方法论同 C 层变异实测）。
# 静默性：全程 A 层。screencapture -l<wid> 按窗口 ID 取位图，不激活、不置前、不动键鼠
#   （QUALITY ㊷-1 实测锁屏下同样有效），故本自测可在你锁屏/用机时自主执行。
# 退出码：0 全部通过 / 1 有用例失败 / 2 环境缺项（明确早退，绝不"降级通过"）
# 判据取向：宁可 SKIP 并说明，也不把「环境不具备」记成通过。
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
SH="tools/qa/window-shot.sh"
CHECK="tools/qa/window-live-check.py"
BIN="tools/r1walk/bin"
TMP="$(mktemp -d /tmp/wshots-selftest.XXXXXX)"
fails=0; skips=0
[ -x "$BIN/wl" ] || { echo "❌ 环境缺项：${BIN}/wl 不存在（先 zsh tools/r1walk/build.sh）" >&2; exit 2; }
python3 -c "import PIL" 2>/dev/null || { echo "❌ 环境缺项：无 PIL，活性判据无从自证" >&2; exit 2; }

expect() { # expect <用例名> <期望rc> <实际rc> <附加证据>
  if [ "$2" = "$3" ]; then
    echo "✅ ${1}｜rc=${3} ${4:-}"
  else
    echo "❌ ${1}｜rc=${3} 期望 ${2} ${4:-}"; fails=$((fails + 1))
  fi
}

# T1 参数不足必须拒绝（防止把"漏参数"跑成"随机截一个窗"）
bash "$SH" only >"$TMP/t1.log" 2>&1; rc=$?
expect "T1 参数不足须拒绝" 3 "$rc"

# T2 不存在的 WID 必须诚实失败，且**不得产出占位图**（有图无内容是最坏的假证据）
bash "$SH" "$TMP/t2.png" WID=999999999 >"$TMP/t2.log" 2>&1; rc=$?
if [ -s "$TMP/t2.png" ]; then t2ev="⚠️ 竟产出非零字节占位图"; else t2ev="未产出占位图（诚实失败）"; fi
expect "T2 不存在 WID 须失败且不凑图" 1 "$rc" "$t2ev"

# T3 owner 无命中必须 rc=2，绝不改用相近 ID 凑数
bash "$SH" "$TMP/t3.png" ZZZNoSuchWindowZZZ >"$TMP/t3.log" 2>&1; rc=$?
expect "T3 owner 无命中须 rc=2 不猜窗" 2 "$rc" "$(head -1 "$TMP/t3.log")"

# T4 owner 命中多个时必须拒绝代挑（条件用例：当前环境无同名多窗则 SKIP 并说明）
multi="$("$BIN/wl" 2>/dev/null | awk 'index($0,"owner=") {
    if (match($0, /owner=[^ ]*/)) { o = substr($0, RSTART + 6, RLENGTH - 6); c[o]++ }
  } END { for (k in c) if (c[k] > 1) { print k; exit } }')"
if [ -n "$multi" ]; then
  bash "$SH" "$TMP/t4.png" "$multi" >"$TMP/t4.log" 2>&1; rc=$?
  expect "T4 owner 多义须拒绝代挑" 2 "$rc" "owner=「${multi}」多命中"
else
  echo "⏭️ T4 SKIP：当前无同名多窗口，无法构造多义（不假装通过）"; skips=$((skips + 1))
fi

# T5 活性判据必须拦住纯色图/底图：现场构造一张 24x24 纯色 PNG（零外部依赖）
python3 - "$TMP/solid.png" <<'PYEOF'
import struct, sys, zlib
w = h = 24
raw = b"".join(b"\x00" + b"\x10\x20\x30" * w for _ in range(h))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
PYEOF
python3 "$CHECK" "$TMP/solid.png" "自测-纯色构造图" >"$TMP/t5.log" 2>&1; rc=$?
expect "T5 纯色图须判活性不达标作废" 4 "$rc" "$(tail -1 "$TMP/t5.log")"

# T6 真实窗口成功路径：rc=0 且活性达标（锁屏下亦应成立）
realwid="$("$BIN/wl" 2>/dev/null | awk 'index($0, "WID=") {
    match($0, /WID=[0-9]+/);  w  = substr($0, RSTART + 4, RLENGTH - 4)
    match($0, /name=[^ ]*/);  nm = substr($0, RSTART + 5, RLENGTH - 5)
    match($0, /w=[0-9]+/);    ww = substr($0, RSTART + 2, RLENGTH - 2)
    if (nm != "" && ww + 0 >= 200 && ww + 0 <= 4000) { print w; exit }
  }')"
if [ -n "$realwid" ]; then
  bash "$SH" "$TMP/t6.png" "WID=${realwid}" >"$TMP/t6.log" 2>&1; rc=$?
  expect "T6 真实窗口须 rc=0 且活性达标" 0 "$rc" "$(grep -o '活性自证:.*' "$TMP/t6.log" | head -1)"
else
  echo "⏭️ T6 SKIP：wl 无合法窗口（幻影行已排除）"; skips=$((skips + 1))
fi

echo "=== window-shot 自测：失败=${fails} 跳过=${skips}｜产物目录 ${TMP}（含屏幕内容，本机留存不入仓）==="
[ "$fails" -eq 0 ] || exit 1
exit 0
