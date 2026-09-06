#!/usr/bin/env bash
# window-shot.sh —— 只读窗口取证（A 层）＋ 内容活性自证（QUALITY ㊷-2 的 SOP 工具化）。
#
# 静默性（铁律 8）：screencapture -l<windowID> 按窗口 ID 取位图，不激活、不置前、不动键鼠、
#   不改变任何窗口可见状态；实测锁屏下同样有效（㊷-1）。因此本脚本属 A 层，可自主执行。
# 存在理由：09-06 差点把「rc=0 的 429KB 文件」当成有效证据——若那张图是空图/底图，
#   后续所有对标结论都会建立在不存在的证据上。故活性自证不是可选项，是门槛。
#
# 用法：tools/qa/window-shot.sh <输出.png> <WID=1234 | owner子串>
#   · 传 owner 子串时多命中 ⇒ 列出候选并退出 2（**绝不猜一个来截**）。
# 退出码：0 取证成功且活性达标 / 1 截图失败 / 2 选择歧义或无命中 / 3 参数错 / 4 活性不达标（产物作废）
set -uo pipefail
if [ "$#" -ne 2 ]; then
  echo "用法: $0 <输出.png> <WID=1234 | owner子串>" >&2
  exit 3
fi
OUT="$1"; SEL="$2"
BIN="$(dirname "$0")/../r1walk/bin"
LOCK="$("$BIN/lockprobe2" 2>/dev/null | head -1)"
WL="$("$BIN/wl" 2>/dev/null || true)"

wid=""
if [ "${SEL#=}" != "$SEL" ] || [[ "$SEL" == WID=* ]]; then
  wid="${SEL#WID=}"
else
  # 只认 owner 命中且「有 name 且宽度在 200..4000」的行——排除 wl 的幻影缩略行（在册 27beta 坑）
  mapfile_tmp="$(printf '%s\n' "$WL" | awk -v pat="$SEL" '
      index($0,"owner=") && index($0, pat) {
        match($0, /WID=[0-9]+/); w=substr($0, RSTART+4, RLENGTH-4)
        match($0, /name=[^ ]*/); nm=substr($0, RSTART+5, RLENGTH-5)
        match($0, /w=[0-9]+/);    ww=substr($0, RSTART+2, RLENGTH-2)
        if (nm != "" && ww+0 >= 200 && ww+0 <= 4000) print w"\t"nm"\t"ww
      }')"
  n=$(printf '%s\n' "$mapfile_tmp" | grep -c . || true)   # 命中数（grep -c 空输入时输出 0 并返回 1，故 || true）
  if [ "$n" -eq 0 ]; then
    echo "无命中：owner 含「${SEL}」的有效窗口不存在（幻影缩略行已排除）。禁止改用相近 ID 凑数。" >&2
    exit 2
  fi
  if [ "$n" -gt 1 ]; then
    echo "选择歧义：「${SEL}」命中 $n 个窗口，请改用 WID= 指定（本脚本绝不代你挑一个）：" >&2
    printf '%s\n' "$mapfile_tmp" | sed 's/^/  WID=/' >&2
    exit 2
  fi
  wid="$(printf '%s' "$mapfile_tmp" | cut -f1)"
fi

echo "锁态: ${LOCK:-未知}｜目标 WID=$wid" >&2
screencapture -o -x -l"$wid" "$OUT" 2>&1
rc=$?
[ "$rc" -ne 0 ] && { echo "截图失败 rc=${rc}（诚实失败，不产出占位图）" >&2; exit 1; }

exec python3 "$(dirname "$0")/window-live-check.py" "$OUT" "$LOCK"
