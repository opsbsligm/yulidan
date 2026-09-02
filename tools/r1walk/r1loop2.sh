#!/bin/zsh
# exec 可信会话专用循环：解锁 + TCC 权限自检通过 才跑 r1walk4（SKIP_N/SKIP_45 精简），防零权轮
WIDPROBE(){ /Users/liguangming/harness-wt/wl | grep 'owner=Harness' | awk '$0 ~ /w=1[0-9]{3}/ {sub(/^WID=/,"",$1); print $1; exit}'; }
while true; do
  if ! /tmp/lockprobe2 | grep -q "ScreenIsLocked: -1"; then sleep 30; continue; fi
  PID=$(pgrep -f "HarnessApp.app/Contents/MacOS/HarnessApp" | head -1)
  if [ -z "$PID" ]; then
    # 解锁后应用未跑（重启/被杀场景）：主动拉起一次再判，防无限空等
    print -r -- "[$(date '+%H:%M:%S')] Harness 未运行 → open -b 拉起"
    open -b com.deepseek.harness; sleep 6
    PID=$(pgrep -f "HarnessApp.app/Contents/MacOS/HarnessApp" | head -1)
    [ -z "$PID" ] && { sleep 30; continue; }
  fi
  WID=$(WIDPROBE)
  if [ -z "$WID" ]; then open -b com.deepseek.harness; sleep 3; WID=$(WIDPROBE); [ -z "$WID" ] && { sleep 30; continue; }; fi
  screencapture -x -o -l$WID /Users/liguangming/harness-wt/walk3/.perm_probe.png 2>/dev/null
  if [ -s /Users/liguangming/harness-wt/walk3/.perm_probe.png ]; then
    print -r -- "[$(date '+%H:%M:%S')] 权限自检 OK（截图落盘），开始精简走测 #3/#6/#7/#8"
    rm -f /Users/liguangming/harness-wt/walk3/.done_v43
    SKIP_N=1 SKIP_45=1 /bin/zsh /Users/liguangming/harness-wt/r1walk4.sh 120
    print -r -- "[$(date '+%H:%M:%S')] 本轮完成 rc=$?"
    if [ -f /Users/liguangming/harness-wt/walk3/.done_v43 ]; then
      # 证据冻结（补记⑧教训②）：可变路径→不可变快照，防后续轮/人工覆盖
      SNAP="/Users/liguangming/harness-wt/walk3_final_$(date +%m%d_%H%M)"
      cp -R /Users/liguangming/harness-wt/walk3 "$SNAP" && print -r -- "证据快照已冻结 → $SNAP"
      exit 0
    fi
  else
    print -r -- "[$(date '+%H:%M:%S')] 零权上下文（screencapture 空），不跑，30s 后重试探针"
  fi
  sleep 30
done
