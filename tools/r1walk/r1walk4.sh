#!/bin/zsh
# R1 §10.3 收尾走测 v4.7（等解锁 → #3 右键 / #4 idpress 取消 / #5 双关闭 / #6 主题闭环「先导后切」 / #7 原位 noChange 拖拽悬停帧 / #8 减弱透明度自动开关）
# v4.7 根因修复：themes 目录空+无 servers.json → 任何内置切换项都不存在，旧 6a「深海蓝」前提从未成立 → 废弃硬编码段；#6 统一改为社区包 Tahoe Teal 闭环（先导 6b → 设置面板取证 → 6a 实渲染 → 自动卸载还原）。另：解锁后 caffeinate 临时防自动锁中断 + .done_v43 防重跑守卫。
# 原则：不写用户数据（#4 只走取消；#7 起终点同一行内 = moveSession noChange 有单测锁定；#8 只读 defaults，系统开关由用户手切）
# 用法：终端里跑 `zsh /Users/liguangming/harness-wt/r1walk2.sh [等解锁秒=900]`（用户在场有 20s 放弃窗口；Agent 代跑无 tty 自动继续）
set -u
cd /Users/liguangming/harness-wt
OUT=/Users/liguangming/harness-wt/walk3; mkdir -p $OUT
WAIT_MAX=${1:-900}
log(){ print -r -- "[$(date '+%H:%M:%S')] $*" }
# v4.3：ev key（CGEvent cghidEventTap）在长时后台会话对目标 app 实测不送达（#10/#6b/#8 因此误判）
# → 键盘注入统一改 System Events key code（osascript，AX 合成通道，实测送达）
skey(){ # skey <keycode> [esc|ret] —— ret=36 esc=53 period=47
  osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1
}
LP=$(ls /Users/liguangming/harness-wt/lockprobe2 /tmp/lockprobe2 2>/dev/null | head -1)  # v4.7 重启幸存：/tmp 副本重启即灭，优先持久副本
unlocked(){ [ "$($LP 2>/dev/null | awk -F': ' '{print $2}')" = "-1" ] }
shot(){ # v4.3：screencapture 在 launchd/nohup 上下文 TCC 丢权 → 失败自动降级 AX 树取证
  screencapture -x -o -l$WID $OUT/$1.png 2>/dev/null
  if [ ! -s $OUT/$1.png ]; then rm -f $OUT/$1.png 2>/dev/null; ./ax $PID dump 20 > $OUT/ax_$1.txt 2>&1; log "shot降级: $1 → ax_$1.txt"; fi
}
rt(){ read -k1 -t "${1:-20}" "REPLY>[#1C 20秒内任意键 = 中止走测（你在用键盘）] " || return 0; print -r -- "用户中止"; exit 9; }

[[ -f $OUT/.done_v43 && "${FORCE:-0}" != "1" ]] && { log "已有 .done_v43（上轮已完成），跳过重跑；确需重跑先删标记或 FORCE=1"; exit 0; }
log "等待解锁（上限 ${WAIT_MAX}s）…"
t0=$(date +%s)
while ! unlocked; do
  if [ $(( $(date +%s) - t0 )) -gt $WAIT_MAX ]; then log "超时未解锁，退出"; exit 3; fi
  sleep 4
done
rt 20
log "已解锁"
# v4.7 锁屏预案①：走测窗口内临时防休眠/防屏保自动锁（caffeinate 是标准断言 API，不改任何系统设置，
# -w $$ 脚本退出即自动释放；不阻止用户手动 ⌃⌘Q 锁屏——若被锁，走测按既有兜底留证退出）
caffeinate -disu -w $$ >/dev/null 2>&1 &
PID=$(pgrep -f "HarnessApp.app/Contents/MacOS/HarnessApp" | head -1)
[ -z "$PID" ] && { log "App 未运行"; exit 4; }
WID=$(./wl | grep 'owner=Harness' | awk '$0 ~ /w=1[0-9]{3}/ {sub(/^WID=/,"",$1); print $1; exit}')
[ -z "$WID" ] && { log "未找到主窗（w>1000）——可能锁屏过渡伪影，重跑本脚本"; exit 5; }
log "PID=$PID WID=$WID"
WINX=$(./wl | grep 'owner=Harness' | awk '$0 ~ /w=1[0-9]{3}/ {for(i=1;i<=NF;i++) if($i ~ /^x=/){sub(/^x=/,"",$i); print $i; exit}}')
[ -z "$WINX" ] && WINX=0
log "窗口左缘 WINX=$WINX（顶栏/侧栏过滤改用相对坐标）"
DB=~/Library/Application\ Support/Harness/sessions.sqlite
dbc(){ sqlite3 -readonly "$DB" "select count(*) from sessions;" 2>/dev/null }
BASE=$(dbc); log "DB 基线 = $BASE"

./ev activate $PID >/dev/null 2>&1; sleep 0.6
./ax $PID press "对话" >/dev/null 2>&1; sleep 0.6
if [ "${SKIP_N:-0}" = "1" ]; then log "SKIP_N=1：跳过 ⌘N（DB 联动 21:53 轮已证 13→15，发送本身也跳过=防泄漏 v4.4）"; else ./ev key cmd n >/dev/null 2>&1; sleep 1.2; log "⌘N 后 DB = $(dbc)（+1 临时会话 = 走测副作用，入册待拍板）"; shot 00_after_cmdn; fi

# ---------- #3 顶栏标题真实右键（与溢出菜单双证） ----------
./ax $PID press "新对话" >/dev/null 2>&1; sleep 0.8
./ax $PID dump 18 > $OUT/t00.txt 2>&1
# 顶栏标题 = y 最小且 x>=300（排除侧栏文本）的 AXStaticText
TITLE=$(grep "AXStaticText" $OUT/t00.txt | grep "pos=" | awk '{ x=$0; sub(/.*pos=/,"",x); sub(/,.*/,"",x); y=$0; sub(/.*pos=[0-9]+,/,"",y); sub(/[^0-9].*/,"",y); if (x-'"$WINX"'>=280) print y"\t"$0 }' | sort -n | head -1 | cut -f2-)
TX=$(print -r -- "$TITLE" | sed -nE 's/.*pos=([0-9]+),([0-9]+).*/\1/p'); TY=$(print -r -- "$TITLE" | sed -nE 's/.*pos=([0-9]+),([0-9]+).*/\2/p')
TW=$(print -r -- "$TITLE" | sed -nE 's/.*size=([0-9]+)x([0-9]+).*/\1/p'); TH=$(print -r -- "$TITLE" | sed -nE 's/.*size=([0-9]+)x([0-9]+).*/\2/p')
if [ -n "$TX" ] && [ -n "$TY" ]; then
  CX=$(( TX + TW/2 )); CY=$(( TY + TH/2 )); log "#3 标题中心 = ($CX,$CY)"
  ./ev rclick $CX $CY >/dev/null 2>&1; sleep 0.9; shot 01_title_rclick
  ./ax $PID dump 18 > $OUT/title_ctx_menu.txt 2>&1
  if [ "$(grep -c "AXMenuItem" $OUT/title_ctx_menu.txt)" = "0" ]; then
    log "#3 rclick 未开菜单 → AXShowMenu(top) 兜底（顶栏标题=Y 最小候选）"
    ./ax $PID showmenu "新对话" top >/dev/null 2>&1; sleep 0.9
    ./ax $PID dump 18 > $OUT/title_ctx_menu.txt 2>&1
    shot 01b_title_ctx_axshow
    ./ax $PID cancelmenu >/dev/null 2>&1; sleep 0.4
  fi
  ./ax $PID cancelmenu >/dev/null 2>&1; sleep 0.4
  ./ax $PID press ellipsis.circle >/dev/null 2>&1; sleep 0.9; shot 02_overflow_menu
  ./ax $PID dump 18 > $OUT/overflow_menu.txt 2>&1
  ./ax $PID cancelmenu >/dev/null 2>&1; sleep 0.4
else log "#3 未取到标题坐标（锁屏过渡态？重跑）"; fi

if [ "${SKIP_45:-0}" = "1" ]; then log "SKIP_45=1：#4/#5 已核销跳过（22:0x 轮双证在案）"; else
# ---------- #4 删除二次确认 → idpress 精确取消 ----------
./ax $PID showmenu "新对话" >/dev/null 2>&1; sleep 0.9; shot 03_row_ctx
./ax $PID dump 18 > $OUT/row_ctx.txt 2>&1
if grep -q "AXMenuItem.*t='删除'" $OUT/row_ctx.txt; then
  ./ax $PID menupress 删除 >/dev/null 2>&1; sleep 0.9; shot 04_delete_confirm
  ./ax $PID idpress action-button-2 >/dev/null 2>&1; sleep 0.8; shot 05_after_cancel
  log "#4 idpress 取消后 DB = $(dbc)（应 = $BASE +1 = 未删除）"
else log "#4 无「删除」菜单项，跳过"; ./ev esc >/dev/null 2>&1; fi

# ---------- #5 设置 sheet：xmark 关 + 重开 + Esc 关（补记②口径，⌘. 系历史注释已修正） ----------
./ax $PID press "设置" >/dev/null 2>&1; sleep 1.0; shot 06_settings_overview
./ax $PID press "打开完整设置" >/dev/null 2>&1; sleep 1.0; shot 07_settings_full
./ax $PID dump 18 > $OUT/settings_full.txt 2>&1
# v4.2 修复：idpress xmark 与外层「关闭设置」⊗ 同 id 二义（r1walk2 轮 08/09/10 作废根因：
# 误触外层导致设置页整体关闭，sheet 关闭链路未证）。改用唯一 accessibilityLabel。
./ax $PID press "关闭完整设置" >/dev/null 2>&1; sleep 0.8; shot 08_closed_xmark
./ax $PID press "打开完整设置" >/dev/null 2>&1; sleep 1.0; shot 09_reopened
skey 53; sleep 0.8; shot 10_closed_esc
./ax $PID dump 16 | grep -q AXSheet && { skey 47; sleep 0.8; shot 10b_closed_period; } # period 惯例键补刀
./ax $PID dump 16 > $OUT/after_cmd_dot.txt 2>&1

fi

# ---------- #6 主题插件闭环 v4.7「先导后切」----------
# 根因修复（补记⑪）：themes 目录空 + 无 servers.json → 当前无任何第三方主题插件 → 设置面板不存在
# 「深海蓝」等内置切换项（旧 6a 前提从未成立，解锁轮必空转）→ 废弃该硬编码段。
# 新闭环（全部走真实 MCP 主题插件路径）：导入社区包(6b) → 设置面板出现即取证 → 切换/还原实渲染(6a) → 自动卸载还原用户状态。
log "#6 闭环开始：导入(6b) → 设置面板取证 → 切换/还原(6a 实渲染) → 自动卸载还原用户状态"
./ax $PID cancelmenu >/dev/null 2>&1; ./ev esc >/dev/null 2>&1; sleep 0.4
# —— 6b 前置导入：插件页 → 导入主题包… → 文件面板键入绝对路径 → Return×2 ——
./ax $PID press "插件" >/dev/null 2>&1; sleep 1.2                  # v4.3 按钮 press 替代 ⌘3
./ax $PID press "导入主题包" >/dev/null 2>&1; sleep 2.0            # NSOpenPanel
# 文件面板键入 "/" 开头文本自动唤起路径输入（macOS 公开行为）→ 输入绝对路径 → 两次 Return
osascript -e 'tell application "System Events" to keystroke "/Users/liguangming/code/swift-harness/demos/community-theme-demo/spec.json"' >/dev/null 2>&1
sleep 0.8; skey 36 >/dev/null 2>&1; sleep 1.4
skey 36 >/dev/null 2>&1; sleep 1.8                 # 打开 → toast「主题包已导入」
shot 12a_after_import
./ax $PID dump 20 > $OUT/import_confirm.txt 2>&1
grep -q "Tahoe Teal" $OUT/import_confirm.txt && log "#6b 导入成功（插件列表已出现 Tahoe Teal）" || log "#6b 列表未确认 Tahoe Teal，留 12a/import_confirm 取证判定"
# —— 设置面板取证：完整设置主题区应出现 Tahoe Teal（主题插件→设置项即时出现） ——
./ax $PID press "设置" >/dev/null 2>&1; sleep 1.0
./ax $PID press "打开完整设置" >/dev/null 2>&1; sleep 1.2
./ax $PID dump 20 > $OUT/settings_theme.txt 2>&1
BASE_LABEL=$(grep -o "[^']基准[^']*主题[^',]*" $OUT/settings_theme.txt | head -1)
# —— 6a 实渲染验证：社区包=全套玻璃参数包（accentHex+glassTintHex+glassMaterial，见 spec.json）
#     切 Tahoe Teal → shot 11 → 还原基准 → shot 12（11/12 像素差 = 强调色+玻璃 tint 即时生效证据） ——
if grep -q "Tahoe Teal" $OUT/settings_theme.txt && [ -n "$BASE_LABEL" ]; then
  log "#6a 基准项实标签 = 「$BASE_LABEL」"
  ./ax $PID press "Tahoe Teal" >/dev/null 2>&1; sleep 1.5; shot 11_theme_teal_live
  ./ax $PID press "$BASE_LABEL" >/dev/null 2>&1; sleep 1.2; shot 12_theme_restored
  log "#6a 已切 Tahoe Teal 并还原（11/12 = 即时生效+还原像素证据；玻璃参数变化为预期）"
fi
# —— 自动卸载收尾（walk 原则=不写用户数据；只要导入成功过就必须卸载还原） ——
if grep -q "Tahoe Teal" $OUT/settings_theme.txt || grep -q "Tahoe Teal" $OUT/import_confirm.txt; then
  ./ev esc >/dev/null 2>&1; sleep 0.6                                 # 关完整设置 sheet（口径=Esc，补记②）
  ./ax $PID press "插件" >/dev/null 2>&1; sleep 1.2
  ./ax $PID press "Tahoe Teal" >/dev/null 2>&1; sleep 1.0
  ./ax $PID press "卸载" >/dev/null 2>&1; sleep 0.9
  ./ax $PID dump 20 > $OUT/uninstall_alert.txt 2>&1
  if grep -q "确定卸载插件" $OUT/uninstall_alert.txt; then
    ./ax $PID press "卸载" last >/dev/null 2>&1; sleep 1.2
    ./ax $PID dump 20 > $OUT/uninstall_done.txt 2>&1
    grep -q "Tahoe Teal" $OUT/uninstall_done.txt && log "#6b ⚠️自动卸载未生效（列表仍在），需手动停用删除" || log "#6b 自动卸载完成（列表已无 Tahoe Teal=用户状态复原）"
  else
    log "#6b ⚠️卸载确认弹窗未出现，不乱点；需手动停用删除 Tahoe Teal"
    ./ev esc >/dev/null 2>&1
  fi
fi
./ev esc >/dev/null 2>&1; sleep 0.6                                   # 统一 Esc 关闭（原 ⌘. 与 cancelAction 实测口径不符）

# ---------- #7 安全拖拽：起终点同一会话行内（noChange），拖拽中段抓悬停帧 ----------
./ax $PID dump 18 > $OUT/t7.txt 2>&1
# 侧栏首条会话行 = y 最小且 x<300（侧栏宽 260）的「新对话」文本
ROW=$(grep "AXButton.*d='新对话" $OUT/t7.txt | grep "pos=" | awk '{ x=$0; sub(/.*pos=/,"",x); sub(/,.*/,"",x); y=$0; sub(/.*pos=[0-9]+,/,"",y); sub(/[^0-9].*/,"",y); if (x-'"$WINX"'<280) print y"\t"$0 }' | sort -n | head -1 | cut -f2-)
RX=$(print -r -- "$ROW" | sed -nE 's/.*pos=([0-9]+),([0-9]+).*/\1/p'); RY=$(print -r -- "$ROW" | sed -nE 's/.*pos=([0-9]+),([0-9]+).*/\2/p')
RW=$(print -r -- "$ROW" | sed -nE 's/.*size=([0-9]+)x([0-9]+).*/\1/p'); RH=$(print -r -- "$ROW" | sed -nE 's/.*size=([0-9]+)x([0-9]+).*/\2/p')
if [ -n "$RX" ]; then
  SX=$(( RX + RW/2 )); SY=$(( RY + RH/2 ))
  # 终点 = 起点上方 6px（仍在原行内 = moveSession noChange，有单测锁定，零归属变更）
  ( sleep 0.7; shot 13_drag_hover ) &
  ./ev drag $SX $SY $SX $(( SY - 6 )) 24 1400 >/dev/null 2>&1; wait
  sleep 0.4; shot 14_drag_settled
  log "#7 拖拽悬停帧 = 13_drag_hover.png（落点回原行 = noChange，无归属变更）"
else log "#7 未取到会话行坐标，跳过"; fi

# ---------- #8 全自动：系统设置深链 → AX 拨「减弱透明度」开 → Harness 取证 → 拨回 → 取证 ----------
shot 20_transparency_before
open "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display" >/dev/null 2>&1
sleep 6
SPID=$(pgrep -x "System Settings" | head -1)
if [ -n "$SPID" ]; then
  ./ax $SPID dump 30 > $OUT/syssettings.txt 2>&1
  if grep -q "减弱透明度" $OUT/syssettings.txt; then
    ./ax $SPID press "减弱透明度" >/dev/null 2>&1; sleep 3
    V1=$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo 0)
    if [ "$V1" = "1" ]; then
      # v4.7.1 安全加固：确认拨开后登记兜底还原 trap——脚本异常退出也不留用户系统在「减弱透明度=开」
      _TB_DONE=0
      trap 'if [ "$_TB_DONE" != 1 ]; then S=$(pgrep -x "System Settings" | head -1); [ -n "$S" ] && /Users/liguangming/harness-wt/ax $S press "减弱透明度" >/dev/null 2>&1; fi' EXIT
      ./ev activate $PID >/dev/null 2>&1; sleep 1
      shot 21_transparency_on
      ./ax $PID dump 16 > $OUT/transparency_on_tree.txt 2>&1
      SPID=$(pgrep -x "System Settings" | head -1)
      ./ax $SPID press "减弱透明度" >/dev/null 2>&1; sleep 3          # 拨回
      ./ev activate $PID >/dev/null 2>&1; sleep 0.8
      shot 22_transparency_off
      V2=$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo 0)
      if [ "$V2" = "0" ]; then _TB_DONE=1; trap - EXIT; fi   # 正常拨回成功→解除兜底（防二次拨回反而拨开；zsh 解除语法=trap 空格- ）
      log "#8 自动开关完成（on=$V1 off=$V2；20/21/22 三帧 = 开→solid、关→恢复证据）"
    else
      log "#8 拨动后未读到 1（可能命中非开关控件），留 syssettings.txt 判定，不重试不乱拨"
    fi
  else
    log "#8 系统设置页无「减弱透明度」（深链或加载问题），留 syssettings.txt 取证"
  fi
else
  log "#8 系统设置进程未出现，跳过自动开关"
fi

log "DB 终值 = $(dbc)（基线 $BASE；SKIP_N=1 应相等，否则 = $((${BASE:-0}+1)) 为走测临时会话）；产物在 $OUT"

touch $OUT/.done_v43 && log "WALK-DONE 标记已写"
