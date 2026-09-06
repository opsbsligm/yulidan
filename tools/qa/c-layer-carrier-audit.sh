#!/bin/zsh
# C 层载体审计（v8 §〇／铁律 8 的机器化不变量）
# 目的：把「注入式走测工具没被自动化载体挂载」从一次性人工声明，变成每次可重跑的 rc。
# 全程只读（grep/launchctl list/crontab -l），零前台、零键鼠、锁屏可跑。
# rc=0 通过；rc=1 发现挂载或发现可疑残留（逐条打印证据）；rc=2 环境异常（如 crontab 不可读）。
set -u

# ★ 解释器自守门（09-06 实证教训）：本脚本是 zsh 脚本（用 setopt／print -r），
#   但 tools/r1walk/README.md 一度记载用 `bash` 调用 ⇒ 实测 rc=2 硬失败，
#   且报错是「syntax error: unexpected end of file」，连读两轮都被它误导成「脚本坏了」，
#   差点去"修"一个本来健康的脚本（zsh -n rc=0）。故：解释器不对时给**可行动**的错误，不报语法错。
if [ -z "${ZSH_VERSION:-}" ]; then
  printf '%s\n' "❌ 本脚本必须用 zsh 跑（shebang 即 #!/bin/zsh）。请用：zsh $0  或  $0" \
                 "   用 bash 跑会因 setopt/print -r 直接语法失败（rc=2），不是脚本本身损坏。" >&2
  exit 2
fi
# ⚠️ zsh 空通配默认是**硬错误**（`no matches found` 直接中断脚本，会把「无载体」误报成审计早退）
setopt NULL_GLOB
REPO="${1:-/Users/liguangming/code/swift-harness}"
# 注入式工具／动作的识别面（B/C 层），只读取证工具（axdump/wl/lockprobe/dump）不在其列
# 检测面＝README 权威分层表的 B/C 层载体名（tools/r1walk/README.md:18-21），不是「提到 r1walk 就报」。
# ⚠️ 09-06 精确化缘由（实证，非放宽）：旧 PAT 里的裸 token「r1walk」把「引用 r1walk/bin 下的
#    A 层只读工具」也判成违规——新 tools/qa/window-shot.sh 仅复用 bin/wl＋bin/lockprobe2（README 明标
#    「不加限，纯只读，锁屏可跑」）就被误报 rc=1。整目录 token 与权威分层表冲突，故精确到具体 C 层脚本名。
#    双向变异实测见 QUALITY ㊸（正例 rc=0／两类反例均 rc=1），确保此次改动未削弱检测面。
# ⚠️ 已知局限（诚实标注，不假装完美）：形如「$BIN/ev activate」（变量拼路径、无 bin/ 字面）不命中本面；
#    旧 PAT 同样不命中，故非本次引入的回归。真正的强制力在工具**自身**的 exit 78 双条件闸门（见 README 二次升级节），
#    本审计只是「载体侧」的第二道防线。
PAT='r1walk/(r1walk4|r1loop2)\.sh|r1loop|bin/(ev|evtype)([[:space:]]|$)|evtype|ax[.]bin|ax .*(press|showmenu)|System Events.*key code|cghidEventTap'
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
      /*.sh) [ -e "$arg" ] || note "⚠️ 残留：$p 指向不存在的脚本 ${arg}（G3 终态要求 launchd 仅剩 App＋ci11.pr）" ;;
    esac
  done
done

if [ "$rc" = "0" ]; then note "✅ 无任何自动化载体挂载 B/C 层注入式工具"; fi
exit "$rc"
