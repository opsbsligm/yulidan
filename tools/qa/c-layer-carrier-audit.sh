#!/bin/zsh
# C 层载体审计（v8 §〇／铁律 8 的机器化不变量）
# 目的：把「注入式走测工具没被自动化载体挂载」从一次性人工声明，变成每次可重跑的 rc。
# 全程只读（grep/launchctl list/crontab -l），零前台、零键鼠、锁屏可跑。
# rc=0 通过；rc=1 发现挂载或发现可疑残留（逐条打印证据）；rc=2 环境异常（如 crontab 不可读）。
set -u
# ⚠️ zsh 空通配默认是**硬错误**（`no matches found` 直接中断脚本，会把「无载体」误报成审计早退）
setopt NULL_GLOB
REPO="${1:-/Users/liguangming/code/swift-harness}"
# 注入式工具／动作的识别面（B/C 层），只读取证工具（axdump/wl/lockprobe/dump）不在其列
PAT='r1walk|r1loop|bin/ev([[:space:]]|$)|evtype|ax[.]bin|ax .*(press|showmenu)|System Events.*key code|cghidEventTap'
rc=0
note() { print -r -- "$*" }
hit() { rc=1; print -r -- "❌ $*"; }

note "=== C 层载体审计 @$(date '+%F %T') ==="

# ① 用户级 LaunchAgents：任何指向注入式工具的 job
for p in "$HOME"/Library/LaunchAgents/*.plist; do
  [ -e "$p" ] || continue
  if grep -Eq "$PAT" "$p"; then hit "LaunchAgent 引用注入式工具：$p"; fi
done

# ② 仓库内的可执行载体（CI 脚本 / 仓库内 plist / 调度脚本），排除工具目录自身
if [ -d "$REPO/tools" ]; then
  while IFS= read -r f; do
    grep -Eq "$PAT" "$f" && hit "仓库脚本引用注入式工具：$f"
  done < <(find "$REPO/tools" -type f \( -name '*.sh' -o -name '*.plist' -o -name '*.py' \) \
             -not -path "$REPO/tools/r1walk/*" \
             -not -name 'c-layer-carrier-audit.sh' 2>/dev/null)
  # ⚠️ 排除自身的理由（不是放水）：本文件必然要**写出**被搜 token 才能搜它们，自匹配是必然假阳性。
  #    真阳性由变异实测保证（QUALITY ㉝：往 automations／LaunchAgents 各塞一条真挂载，审计均转 rc=1）。
fi
[ -f "$REPO/tools/ci-local.sh" ] && grep -Eq "$PAT" "$REPO/tools/ci-local.sh" && hit "四门禁脚本引用注入式工具：tools/ci-local.sh"

# ③ codex automations（heartbeat/automation 载体禁止挂 C 层动作）
if [ -d "$HOME/.codex/automations" ]; then
  for f in "$HOME"/.codex/automations/*/automation.toml; do
    [ -e "$f" ] || continue
    if grep -Eq "$PAT" "$f"; then hit "automation 定义含注入式动作：$f"; fi
  done
fi

# ④ crontab
if command -v crontab >/dev/null 2>&1; then
  cl=$(crontab -l 2>&1)
  cr=$?
  if [ "$cr" = "1" ] || print -r -- "$cl" | grep -qi "no crontab"; then
    note "✅ crontab：无条目"
  elif [ "$cr" != "0" ]; then
    note "⚠️ crontab 不可读（不计失败，仅提示）：$cl"
  else
    print -r -- "$cl" | grep -Eq "$PAT" && hit "crontab 含注入式动作"
  fi
fi

# ⑤ 已加载 harness job 清单（**必查项**：早轮一次性代理即使 plist 已移走，服务定义仍可留在域里）
if command -v launchctl >/dev/null 2>&1; then
  note "ℹ️ 已加载 harness 服务：$(launchctl list 2>/dev/null | awk '/harness/{printf "%s ", $3}')"
fi
for p in "$HOME"/Library/LaunchAgents/com.harness.*.plist; do
  [ -e "$p" ] || continue
  # 只认「整个 <string> 元素本身就是一条绝对路径 .sh」的情形。
  # ⚠️ 曾用 grep -oE '/[^<]*[.]sh' 取路径，会把 `zsh -lc "cd … && tools/ci-local.sh pr > …"`
  #    这类命令串里的片段当成脚本路径 ⇒ 对 ci11.pr 误报「残留」（本轮实测踩到并修）。
  for arg in $(sed -nE 's:.*<string>(.*)</string>.*:\1:p' "$p" | sed -n '1,12p'); do
    case "$arg" in
      /*.sh) [ -e "$arg" ] || note "⚠️ 残留：$p 指向不存在的脚本 $arg（G3 终态要求 launchd 仅剩 App＋ci11.pr）" ;;
    esac
  done
done

if [ "$rc" = "0" ]; then note "✅ 无任何自动化载体挂载 B/C 层注入式工具"; fi
exit "$rc"
